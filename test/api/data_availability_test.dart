/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _MockMetadataProvider implements MetadataProvider {
  final Map<String, MetadataModel> _map;

  _MockMetadataProvider(this._map);

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => _map;

  @override
  Future<MetadataModel?> getMetadata(String name) async => _map[name];

  @override
  Future<void> fetchMetadatas() async {}

  @override
  bool get loading => false;

  @override
  dynamic get error => null;

  @override
  String? get prefix => null;

  @override
  String get scope => '';

  @override
  void setPrefix(String? newPrefix) {}
}

MetadataModel _model(String name, {required String mode}) => MetadataModel(
  name: name,
  apiName: '${name}s',
  label: name,
  labelPlural: '${name}s',
  searchable: false,
  sortable: false,
  synchronizable: mode != 'none',
  synchronizableMode: mode,
  fields: const {},
);

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi(
    super.basePath, {
    required Fetcher fetcher,
    LocalStore? localStore,
    Outbox? outbox,
  }) : super(
         fetcher: fetcher,
         offlineBindings: localStore == null
             ? null
             : OfflineStores(localStore: localStore, outbox: outbox),
       );

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  int? refuseWith;
  List<Map<String, dynamic>> items = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    final refusal = refuseWith;

    if (refusal != null) {
      return ResponseBody.fromString(
        '{"detail": "nope"}',
        refusal,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // A record read: /things/1
    final segments = options.path.split('/');
    final last = segments.last;
    final id = int.tryParse(last);

    if (id != null) {
      final record = items.where((item) => item['id'] == id).firstOrNull;

      if (record == null) {
        return ResponseBody.fromString(
          '{"detail": "Not found"}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }

      return ResponseBody.fromString(
        jsonEncode(record),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'items': items,
        'total': items.length,
        'limit': items.length,
        'offset': 0,
        'total_pages': 1,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late Fetcher fetcher;
  late DriftLocalStore store;
  late Outbox outbox;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    if (!hasService<ApiModelEngineProvider>()) {
      container.registerSingleton<ApiModelEngineProvider>(
        const OfflineApiModelEngineProvider(),
      );
    }

    if (!hasService<MetadataProvider>()) {
      container.registerSingleton<MetadataProvider>(
        _MockMetadataProvider({
          // The three regimes, exactly as the server declares them.
          'thing': _model('thing', mode: 'partial'),
          'mirrored': _model('mirrored', mode: 'full'),
          'strict': _model('strict', mode: 'none'),
        }),
      );
    }
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter;
    fetcher = Fetcher.create(
      dio: dio,
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
      enableErrorTransform: false,
    );
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    outbox = Outbox(store);
  });

  tearDown(() => store.close());

  _ThingApi partialApi() =>
      _ThingApi('/things', fetcher: fetcher, localStore: store, outbox: outbox);

  _ThingApi fullApi() => _ThingApi(
    '/mirroreds',
    fetcher: fetcher,
    localStore: store,
    outbox: outbox,
  );

  // A model the server does not let the client replicate: the online engine,
  // nothing local, nothing buffered.
  _ThingApi strictApi() => _ThingApi('/stricts', fetcher: fetcher);

  group('ApiCollection availability', () {
    test('the server answering marks the read live', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final collection = ApiCollection<_Thing>(partialApi());

      await collection.load();

      expect(collection.availability, DataAvailability.live);
      expect(collection.requiresConnection, isFalse);
      expect(collection.isFromCache, isFalse);
      expect(collection.isEmpty, isFalse);
      expect(collection.canWrite, isTrue);

      collection.dispose();
    });

    test('an answer with no row is a legitimate empty state', () async {
      adapter.items = [];
      final collection = ApiCollection<_Thing>(partialApi());

      await collection.load();

      // The distinction the whole feature exists for: nothing to show, and
      // saying so is honest.
      expect(collection.isEmpty, isTrue);
      expect(collection.requiresConnection, isFalse);
      expect(collection.availability, DataAvailability.live);

      collection.dispose();
    });

    test(
      'an unreachable server with nothing mirrored requires a connection',
      () async {
        adapter.offline = true;
        final collection = ApiCollection<_Thing>(partialApi());

        await collection.load();

        expect(collection.requiresConnection, isTrue);
        // Not an empty state: we do not know whether there is anything.
        expect(collection.isEmpty, isFalse);
        expect(collection.availability, DataAvailability.offline);

        collection.dispose();
      },
    );

    test('a partial model still accepts writes while unreachable', () async {
      adapter.offline = true;
      final collection = ApiCollection<_Thing>(partialApi());

      await collection.load();

      // The list cannot be read, but a create buffers and replays — the New
      // button has to stay enabled.
      expect(collection.requiresConnection, isTrue);
      expect(collection.canWrite, isTrue);

      collection.dispose();
    });

    test(
      'a non-synchronizable model blocks writes while unreachable',
      () async {
        adapter.offline = true;
        final collection = ApiCollection<_Thing>(strictApi());

        await collection.load();

        expect(collection.requiresConnection, isTrue);
        expect(collection.canWrite, isFalse);

        collection.dispose();
      },
    );

    test('mirrored rows served offline are flagged as incomplete', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final collection = ApiCollection<_Thing>(partialApi());
      await collection.load();

      adapter.offline = true;
      await collection.reload();

      expect(collection.items, hasLength(1));
      expect(collection.isFromCache, isTrue);
      // `partial`: what earlier reads happened to bring back, not the truth.
      expect(collection.isIncomplete, isTrue);
      expect(collection.requiresConnection, isFalse);
      expect(collection.canWrite, isTrue);

      collection.dispose();
    });

    test('a fully mirrored model served offline is not incomplete', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final collection = ApiCollection<_Thing>(fullApi());
      await collection.load();

      adapter.offline = true;
      await collection.reload();

      expect(collection.isFromCache, isTrue);
      // The manifest pull makes the mirror complete: an empty result here would
      // be a real empty.
      expect(collection.isIncomplete, isFalse);

      collection.dispose();
    });

    test('a failed reload does not hide the rows it kept', () async {
      // No mirror here: an online-only model keeps its rows in memory, and a
      // banner replacing them would lose the only copy on screen.
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final collection = ApiCollection<_Thing>(strictApi());
      await collection.load();

      adapter.offline = true;
      await collection.reload();

      expect(collection.items, hasLength(1));
      expect(collection.requiresConnection, isFalse);
      expect(collection.availability, DataAvailability.cached);
      // Stale rows and no outbox behind them: acting on them would fail.
      expect(collection.canWrite, isFalse);

      collection.dispose();
    });

    test('a refusal is a failure, not a missing connection', () async {
      adapter.refuseWith = 500;
      final collection = ApiCollection<_Thing>(partialApi());

      await collection.load();

      expect(collection.availability, DataAvailability.failed);
      expect(collection.requiresConnection, isFalse);
      expect(collection.isEmpty, isFalse);
      // The server is up and answering: a write would be delivered or refused,
      // not lost.
      expect(collection.canWrite, isTrue);

      collection.dispose();
    });

    test('a 503 degrades like a lost connection', () async {
      adapter.refuseWith = 503;
      final collection = ApiCollection<_Thing>(partialApi());

      await collection.load();

      expect(collection.availability, DataAvailability.offline);

      collection.dispose();
    });

    test('nothing loaded yet is idle, not empty', () {
      final collection = ApiCollection<_Thing>(partialApi());

      expect(collection.availability, DataAvailability.idle);
      expect(collection.isEmpty, isFalse);
      expect(collection.requiresConnection, isFalse);

      collection.dispose();
    });

    test('connectivity coming back heals a degraded collection', () async {
      adapter.offline = true;
      final collection = ApiCollection<_Thing>(partialApi());
      await collection.load();

      expect(collection.requiresConnection, isTrue);

      adapter.offline = false;
      adapter.items = [
        {'id': 7, 'name': 'Late'},
      ];
      getService<Bus>().fire(
        const SyncStatusChangedEvent(
          online: true,
          syncing: false,
          pending: 0,
          conflicts: 0,
        ),
      );
      // The listener re-reads without a loader; give it the microtasks it needs.
      await pumpEventQueue();

      expect(collection.availability, DataAvailability.live);
      expect(collection.items.single.id, 7);
      expect(collection.error, isNull);

      collection.dispose();
    });

    test('a still-offline reconnect event leaves the verdict alone', () async {
      adapter.offline = true;
      final collection = ApiCollection<_Thing>(partialApi());
      await collection.load();

      getService<Bus>().fire(
        const SyncStatusChangedEvent(
          online: true,
          syncing: false,
          pending: 0,
          conflicts: 0,
        ),
      );
      await pumpEventQueue();

      expect(collection.requiresConnection, isTrue);

      collection.dispose();
    });
  });

  group('ApiRecord availability', () {
    test('the server answering marks the read live', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final record = ApiRecord<_Thing>(partialApi());

      await record.load(1);

      expect(record.availability, DataAvailability.live);
      expect(record.isFromCache, isFalse);
      expect(record.value?.id, 1);

      record.dispose();
    });

    test('a mirrored record served offline is flagged as cached', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final record = ApiRecord<_Thing>(partialApi());
      await record.load(1);

      adapter.offline = true;
      await record.reload();

      // Before getResult, the fallback was indistinguishable from a server
      // answer: a detail screen showed mirror data without being able to say so.
      expect(record.isFromCache, isTrue);
      expect(record.isIncomplete, isTrue);
      expect(record.value?.id, 1);

      record.dispose();
    });

    test('nothing mirrored requires a connection', () async {
      adapter.offline = true;
      final record = ApiRecord<_Thing>(partialApi());

      await record.load(42);

      expect(record.requiresConnection, isTrue);
      expect(record.value, isNull);

      record.dispose();
    });

    test('a missing record is a failure, not a missing connection', () async {
      adapter.items = [];
      final record = ApiRecord<_Thing>(partialApi());

      await record.load(42);

      expect(record.availability, DataAvailability.failed);
      expect(record.requiresConnection, isFalse);

      record.dispose();
    });

    test('connectivity coming back heals a degraded record', () async {
      adapter.offline = true;
      final record = ApiRecord<_Thing>(partialApi());
      await record.load(1);

      expect(record.requiresConnection, isTrue);

      adapter.offline = false;
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      getService<Bus>().fire(
        const SyncStatusChangedEvent(
          online: true,
          syncing: false,
          pending: 0,
          conflicts: 0,
        ),
      );
      await pumpEventQueue();

      expect(record.availability, DataAvailability.live);
      expect(record.value?.id, 1);
      expect(record.error, isNull);

      record.dispose();
    });
  });

  group('getResult', () {
    test('reports the source of a record read', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];
      final api = partialApi();

      expect((await api.getResult(1)).fromCache, isFalse);

      adapter.offline = true;

      expect((await api.getResult(1)).fromCache, isTrue);
    });

    test('an online-only model never reports a cache hit', () async {
      adapter.items = [
        {'id': 1, 'name': 'One'},
      ];

      expect((await strictApi().getResult(1)).fromCache, isFalse);
    });
  });

  group('BaseModel.isOfflinePending', () {
    test('marks a record still waiting for its replay', () {
      expect(
        _Thing({'id': -1, '_offline_pending': true}).isOfflinePending,
        isTrue,
      );
      expect(_Thing({'id': 1}).isOfflinePending, isFalse);
    });
  });
}
