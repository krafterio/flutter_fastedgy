/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

MetadataField _field(String name, String type, {String? placeholder}) =>
    MetadataField(
      name: name,
      label: name,
      type: type,
      readonly: placeholder != null,
      required: false,
      searchable: false,
      extra: false,
      filterOperators: const [],
      localPlaceholder: placeholder,
    );

MetadataModel _flowModel(String mode) => MetadataModel(
  name: 'flow',
  apiName: 'flows',
  label: 'Flow',
  labelPlural: 'Flows',
  searchable: false,
  sortable: false,
  synchronizable: mode != 'none',
  synchronizableMode: mode,
  fields: {
    'name': _field('name', 'char'),
    'reference': _field('reference', 'char', placeholder: 'DRAFT-{seq}'),
  },
);

class _MutableMetadataProvider implements MetadataProvider {
  Map<String, MetadataModel> map = {'flow': _flowModel('partial')};

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => map;

  @override
  Future<MetadataModel?> getMetadata(String name) async => map[name];

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

class _Flow extends BaseModel<_Flow> {
  _Flow(super.data);

  String get name => getString('name') ?? '';

  String? get reference => getString('reference');
}

class _FlowApi extends ApiModel<_Flow> {
  _FlowApi({
    required Fetcher fetcher,
    required LocalStore localStore,
    Outbox? outbox,
    LocalSequence? sequence,
  }) : super(
         '',
         modelName: 'flow',
         fetcher: fetcher,
         offlineBindings: OfflineStores(
           localStore: localStore,
           outbox: outbox,
           sequence: sequence,
         ),
       );

  @override
  _Flow fromJson(Map<String, dynamic> json) => _Flow(json);
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final List<String> calls = [];
  final Map<String, Map<String, dynamic> Function(RequestOptions options)>
  routes = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    final handler = routes['${options.method} ${options.path}'];

    return ResponseBody.fromString(
      jsonEncode(handler?.call(options) ?? const <String, dynamic>{}),
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

  late _MutableMetadataProvider metadatas;
  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late LocalSequence sequence;
  late Outbox outbox;
  late Fetcher fetcher;
  late _FlowApi api;
  late SyncEngine engine;

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

    metadatas = _MutableMetadataProvider();
    container.registerSingleton<MetadataProvider>(metadatas);
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    metadatas.map = {'flow': _flowModel('partial')};

    final db = OfflineDatabase(NativeDatabase.memory());
    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.httpClientAdapter = adapter;
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

    store = DriftLocalStore(databaseOpener: () => db);
    await store.open();
    sequence = LocalSequence(databaseOpener: () => db);
    await sequence.open();
    outbox = Outbox(store);
    api = _FlowApi(
      fetcher: fetcher,
      localStore: store,
      outbox: outbox,
      sequence: sequence,
    );
    engine = SyncEngine(
      outbox,
      fetcher,
      getService<Bus>(),
      localStore: store,
      metadatas: metadatas,
    );
  });

  tearDown(() => store.close());

  group('partial replication', () {
    test('sync pulls no manifest', () async {
      adapter.routes['GET /flows'] = (_) => {
        'items': [
          {'id': 1, 'name': 'One'},
        ],
        'total': 1,
        'limit': 1,
        'offset': 0,
        'total_pages': 1,
      };

      await api.sync();

      // Nothing is pre-downloaded: no manifest, no delta fetch.
      expect(adapter.calls, isEmpty);
    });

    test('a full model still pulls its manifest', () async {
      metadatas.map = {'flow': _flowModel('full')};
      adapter.routes['GET /flows'] = (_) => {
        'items': [
          {'id': 1, 'name': 'One'},
        ],
        'total': 1,
        'limit': 1,
        'offset': 0,
        'total_pages': 1,
      };

      await api.sync();

      expect(adapter.calls, isNotEmpty);
    });

    test('reads fill the mirror as they succeed', () async {
      adapter.routes['GET /flows'] = (_) => {
        'items': [
          {'id': 1, 'name': 'One'},
          {'id': 2, 'name': 'Two'},
        ],
        'total': 2,
        'limit': 2,
        'offset': 0,
        'total_pages': 1,
      };

      final online = await api.list();

      expect(online.fromCache, isFalse);
      // What was read is now readable offline, without any manifest.
      expect(await api.cachedList(), hasLength(2));
    });

    test('a cache fallback is flagged as such', () async {
      adapter.routes['GET /flows'] = (_) => {
        'items': [
          {'id': 1, 'name': 'One'},
        ],
        'total': 1,
        'limit': 1,
        'offset': 0,
        'total_pages': 1,
      };
      await api.list();

      adapter.offline = true;
      final offlineResult = await api.list();

      expect(offlineResult.items, hasLength(1));
      expect(offlineResult.fromCache, isTrue);
    });

    test('sync never prunes what was never read', () async {
      adapter.routes['GET /flows'] = (_) => {
        'items': [
          {'id': 1, 'name': 'One'},
        ],
        'total': 1,
        'limit': 1,
        'offset': 0,
        'total_pages': 1,
      };
      await api.list();

      // A record absent from a partial mirror may simply never have been read,
      // so a sync must not delete anything locally.
      await api.sync();

      expect(await api.cachedList(), hasLength(1));
    });
  });

  group('local placeholder', () {
    test('an offline create shows a provisional reference', () async {
      adapter.offline = true;

      final first = await api.create(_Flow({'name': 'Draft'}));
      final second = await api.create(_Flow({'name': 'Other'}));

      expect(first.reference, 'DRAFT-1');
      expect(second.reference, 'DRAFT-2');
      expect(first.id, -1);
      expect(second.id, -2);
    });

    test('the placeholder never reaches the server', () async {
      adapter.offline = true;

      await api.create(_Flow({'name': 'Draft'}));

      // read_only server-side: the buffered payload stays what was asked for.
      expect((await outbox.all()).single.payload, {'name': 'Draft'});
    });

    test('the server value replaces it on replay', () async {
      adapter.offline = true;
      final draft = await api.create(_Flow({'name': 'Draft'}));

      expect(draft.reference, 'DRAFT-1');

      adapter.offline = false;
      adapter.routes['POST /flows'] = (_) => {
        'id': 42,
        'name': 'Draft',
        'reference': 'FLOW-7',
        'created_at': '2026-07-25T10:00:00',
      };
      await engine.flush();

      final synced = await api.cachedGet(42);

      expect(synced!.reference, 'FLOW-7');
      expect(synced.getBool('_offline_pending'), isNull);
      expect(await api.cachedGet(draft.id!), isNull);
    });

    test('a model without a placeholder gets none', () async {
      metadatas.map = {
        'flow': MetadataModel(
          name: 'flow',
          apiName: 'flows',
          label: 'Flow',
          labelPlural: 'Flows',
          searchable: false,
          sortable: false,
          synchronizable: true,
          synchronizableMode: 'partial',
          fields: {'name': _field('name', 'char')},
        ),
      };
      adapter.offline = true;

      final created = await api.create(_Flow({'name': 'Draft'}));

      expect(created.reference, isNull);
      expect(created.data.containsKey('reference'), isFalse);
    });
  });

  group('the whole offline flow', () {
    test('a flow and its attachments sync with the right owner', () async {
      // The scenario this feature exists for: create a flow offline, attach
      // three files to it, then reconnect. Flow and attachment sequences both
      // start at -1, so nothing may be resolved by id value alone.
      final tempDir = await Directory.systemTemp.createTemp('offline_flow');
      final uploads = PendingUploadStore(
        databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
        directoryOpener: () async => tempDir,
      );
      await uploads.open();

      final uploader = StorageUploader(
        fetcher,
        prefix: '',
        outbox: outbox,
        uploads: uploads,
        sequence: sequence,
      );
      final syncEngine = SyncEngine(
        outbox,
        fetcher,
        getService<Bus>(),
        localStore: store,
        metadatas: metadatas,
        uploads: uploads,
      );

      adapter.offline = true;

      final flow = await api.create(_Flow({'name': 'Onboarding emails'}));

      expect(flow.id, -1);
      expect(flow.reference, 'DRAFT-1');

      final attachments = await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
          'spec.docx': Uint8List.fromList([2]),
          'shot.jpg': Uint8List.fromList([3]),
        },
        filenames: {
          'brief.pdf': 'brief.pdf',
          'spec.docx': 'spec.docx',
          'shot.jpg': 'shot.jpg',
        },
        meta: {
          'record': {'model': 'flow', 'id': flow.id},
        },
      );

      // Overlapping temporary ids across the two models.
      expect(attachments.map((a) => a.id), [-1, -2, -3]);

      // Four things to sync — exactly what the pending badge shows.
      expect(await outbox.all(), hasLength(4));

      adapter.offline = false;
      adapter.routes['POST /flows'] = (_) => {
        'id': 42,
        'name': 'Onboarding emails',
        'reference': 'FLOW-7',
      };

      var nextAttachmentId = 100;
      adapter.routes['POST /storage/upload/attachments'] = (_) => {
        'attachments': [
          {'id': nextAttachmentId++, 'name': 'file'},
        ],
      };

      // Only count what the replay sends, not the attempt that failed offline.
      adapter.calls.clear();
      await syncEngine.flush();

      expect(await outbox.all(), isEmpty);

      // The flow got its real identity.
      final synced = await api.cachedGet(42);
      expect(synced!.reference, 'FLOW-7');

      // And every attachment was associated with the flow — not with the
      // attachment that happened to share its temporary id.
      final sent = adapter.calls
          .where((call) => call.endsWith('/storage/upload/attachments'))
          .length;
      expect(sent, 3);

      for (var id = 100; id < 103; id++) {
        expect(await store.get('attachment', id), isNotNull);
      }

      expect(await uploads.all(), isEmpty);

      await tempDir.delete(recursive: true);
    });
  });
}
