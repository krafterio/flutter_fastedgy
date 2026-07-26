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

import '../helpers/fake_metadata.dart';

class _Flow extends BaseModel<_Flow> {
  _Flow(super.data);
}

class _FlowApi extends ApiModel<_Flow> {
  _FlowApi({required Fetcher fetcher, required LocalStore localStore})
    : super(
        '',
        modelName: 'flow',
        fetcher: fetcher,
        offlineBindings: OfflineStores(localStore: localStore),
      );

  @override
  _Flow fromJson(Map<String, dynamic> json) => _Flow(json);
}

/// A server that answers list reads from a fixture, and can be switched off.
class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  List<Map<String, dynamic>> statuses = [];
  List<Map<String, dynamic>> flows = [];

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

    final isAxis = options.path.endsWith('/flow_statuses');
    final rows = isAxis ? statuses : _matching(options);

    return ResponseBody.fromString(
      jsonEncode({
        'items': rows,
        'total': rows.length,
        'limit': options.queryParameters['limit'] ?? rows.length,
        'offset': 0,
        'total_pages': 1,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  /// The flows a bucket's X-Filter selects, evaluated the way the server would.
  List<Map<String, dynamic>> _matching(RequestOptions options) {
    final raw = options.headers['X-Filter'] as String?;

    if (raw == null) {
      return flows;
    }

    final rule = jsonDecode(raw) as List<Object?>;
    final field = rule.first as String;

    if (rule.length == 2) {
      return flows.where((flow) => flow[field] == null).toList();
    }

    final value = rule[2];

    return flows
        .where((flow) => (flow[field] as Map<String, dynamic>?)?['id'] == value)
        .toList();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late ReplicaStore replicaStore;
  late Fetcher fetcher;
  late _FlowApi api;

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
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    final metadata = fakeMetadataProvider();
    container.registerSingleton<MetadataProvider>(metadata);

    adapter = _ScriptedAdapter()
      ..statuses = [
        {'id': 3, 'name': 'To do'},
        {'id': 7, 'name': 'Doing'},
      ]
      ..flows = [
        {
          'id': 1,
          'name': 'A',
          'status': {'id': 3},
        },
        {
          'id': 2,
          'name': 'B',
          'status': {'id': 3},
        },
      ];

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

    final db = OfflineDatabase(NativeDatabase.memory());
    store = DriftLocalStore(databaseOpener: () => db);
    await store.open();
    replicaStore = ReplicaStore(databaseOpener: () => db);
    await replicaStore.open();
    container.registerSingleton<LocalStore>(store);
    container.registerSingleton<Replica>(Replica(replicaStore, metadata));

    api = _FlowApi(fetcher: fetcher, localStore: store);
  });

  tearDown(() async {
    container.unregister<MetadataProvider>();
    container.unregister<LocalStore>();
    container.unregister<Replica>();
    await store.close();
  });

  Future<GroupedApiCollection<_Flow>> groupedByStatus() async {
    final source = await resolveGroupSource(api, 'status', emptyLabel: 'None');
    final collection = GroupedApiCollection<_Flow>(
      api,
      source!,
      fields: const ['id', 'name', 'status.id', 'status.name'],
    );
    addTearDown(collection.dispose);

    return collection;
  }

  group('a partial model grouped offline', () {
    test('keeps its buckets and counts them locally', () async {
      final online = await groupedByStatus();
      await online.load();
      expect(online.isFromCache, isFalse);

      adapter.offline = true;
      final offline = await groupedByStatus();
      await offline.load();

      // The reads filled the mirror, so the buckets are still there and each
      // one counts what it holds locally.
      expect(offline.entries.map((entry) => entry.group.label), [
        'To do',
        'Doing',
        'None',
      ]);
      expect(offline.entries.first.collection.items.length, 2);
      expect(offline.entries.first.collection.total, 2);
      expect(offline.requiresConnection, isFalse);
      expect(offline.isFromCache, isTrue);
      // The mirror holds what the reads happened to return, not the model: the
      // counts are local counts and the screen has to say so.
      expect(offline.isIncomplete, isTrue);
    });

    test('a bucket with no local match is empty, not disconnected', () async {
      final online = await groupedByStatus();
      await online.load();

      adapter.offline = true;
      final offline = await groupedByStatus();
      await offline.load();

      final doing = offline.entries[1].collection;
      expect(doing.items, isEmpty);
      expect(doing.total, 0);
      expect(doing.isEmpty, isTrue);
      expect(doing.requiresConnection, isFalse);
    });

    test('nothing mirrored is a connection notice', () async {
      adapter.offline = true;
      final offline = await groupedByStatus();

      await offline.load();

      // The axis could not be read either, so there is nothing to show at all.
      expect(offline.entries, isEmpty);
      expect(offline.requiresConnection, isTrue);
    });

    test('a mirrored axis survives without the rows', () async {
      // Only the statuses were ever read online: the axis is a `full` model, so
      // its own sync mirrored it.
      final axis = ApiCollection<GenericBaseModel>(
        GenericApiModel('', modelName: 'flow_status', fetcher: fetcher),
      );
      addTearDown(axis.dispose);
      await axis.load();

      adapter.offline = true;
      final offline = await groupedByStatus();
      await offline.load();

      expect(offline.entries.map((entry) => entry.group.label), [
        'To do',
        'Doing',
        'None',
      ]);
      // Every bucket came back empty-handed: the axis is known, the rows are not.
      expect(offline.requiresConnection, isTrue);
    });
  });
}
