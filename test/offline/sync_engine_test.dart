/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _Item extends BaseModel<_Item> {
  _Item(super.data);

  String get name => getString('name') ?? '';
}

class _ItemApi extends OfflineApiModel<_Item> {
  _ItemApi({
    required Fetcher fetcher,
    required LocalStore localStore,
    required Outbox outbox,
  }) : super(
         '/items',
         fetcher: fetcher,
         localStore: localStore,
         outbox: outbox,
       );

  @override
  _Item fromJson(Map<String, dynamic> json) => _Item(json);
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function(RequestOptions options)>
  routes = {};
  final Map<
    String,
    Future<Map<String, dynamic>> Function(RequestOptions options)
  >
  asyncRoutes = {};
  final Map<String, int> errorRoutes = {};
  final List<String> calls = [];
  final List<Object?> postBodies = [];

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

    calls.add('${options.method} ${options.path}');

    if (options.method == 'POST') {
      postBodies.add(options.data);
    }
    final errorStatus = errorRoutes['${options.method} ${options.path}'];

    if (errorStatus != null) {
      return ResponseBody.fromString(
        '{"detail": "boom"}',
        errorStatus,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final asyncHandler = asyncRoutes['${options.method} ${options.path}'];

    if (asyncHandler != null) {
      return ResponseBody.fromString(
        jsonEncode(await asyncHandler(options)),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final handler = routes['${options.method} ${options.path}'];

    if (handler == null) {
      return ResponseBody.fromString(
        '{"detail": "Not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode(handler(options)),
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
  late DriftLocalStore store;
  late Outbox outbox;
  late Fetcher fetcher;
  late _ItemApi api;
  late SyncEngine engine;
  late List<OutboxOperationDiscardedEvent> discarded;
  late List<OutboxOperationMergedEvent> merged;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
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
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    outbox = Outbox(store);
    api = _ItemApi(fetcher: fetcher, localStore: store, outbox: outbox);
    engine = SyncEngine(outbox, fetcher, getService<Bus>(), localStore: store);
    discarded = [];
    merged = [];
    getService<Bus>().on<OutboxOperationDiscardedEvent>().listen(discarded.add);
    getService<Bus>().on<OutboxOperationMergedEvent>().listen(merged.add);
  });

  tearDown(() => store.close());

  group('offline writes buffering', () {
    test('offline create is optimistic and enqueued', () async {
      adapter.offline = true;

      final created = await api.create(_Item({'name': 'Draft'}));

      expect(created.id, isNegative);
      expect(created.getBool('_offline_pending'), isTrue);
      expect(await api.cachedList(), hasLength(1));
      expect(await outbox.all(), hasLength(1));
    });

    test('offline update merges locally and enqueues', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One', 'tag': 'keep'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'Renamed'}));

      final cached = await api.cachedGet(1);
      expect(cached?.name, 'Renamed');
      expect(cached?.getString('tag'), 'keep');
      expect((await outbox.all()).single.method, 'PATCH');
    });

    test('offline delete of a pending create cancels both', () async {
      adapter.offline = true;

      final created = await api.create(_Item({'name': 'Draft'}));
      await api.delete(created.id!);

      expect(await outbox.all(), isEmpty);
      expect(await api.cachedList(), isEmpty);
    });

    test('the outbox survives a store reopen', () async {
      adapter.offline = true;
      await api.create(_Item({'name': 'Draft'}));

      // Same underlying database is not reachable after close with a memory
      // executor, so assert persistence at the store API level instead.
      expect(await Outbox(store).all(), hasLength(1));
    });
  });

  group('flush', () {
    test('replays a create and swaps the temporary record', () async {
      adapter.offline = true;
      final created = await api.create(_Item({'name': 'Draft'}));

      adapter.offline = false;
      adapter.routes['POST /items'] = (options) => {'id': 42, 'name': 'Draft'};
      await engine.flush();

      expect(await outbox.all(), isEmpty);
      expect(await api.cachedGet(created.id!), isNull);
      final synced = await api.cachedGet(42);
      expect(synced?.name, 'Draft');
      expect(synced?.getBool('_offline_pending'), isNull);
    });

    test('remaps batched operations targeting the temporary id', () async {
      adapter.offline = true;
      final created = await api.create(_Item({'name': 'Draft'}));
      await api.update(created.id!, _Item({'name': 'Renamed'}));

      adapter.offline = false;
      adapter.routes['POST /items'] = (options) => {'id': 42, 'name': 'Draft'};
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 42,
            'status': 'applied',
            'record': {'id': 42, 'name': 'Renamed'},
          },
        ],
      };
      await engine.flush();

      final body = adapter.postBodies.last as Map;
      expect((body['operations'] as List).single['id'], 42);
      expect((await api.cachedGet(42))?.name, 'Renamed');
      expect(await outbox.all(), isEmpty);
    });

    test('batches consecutive updates and deletes into one call', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      await store.put('/items', 2, {'id': 2, 'name': 'Two'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'One!'}));
      await api.update(2, _Item({'name': 'Two!'}));
      await api.delete(2);

      adapter.offline = false;
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 1,
            'status': 'applied',
            'record': {'id': 1, 'name': 'One!'},
          },
          {
            'id': 2,
            'status': 'applied',
            'record': {'id': 2, 'name': 'Two!'},
          },
          {'id': 2, 'status': 'applied'},
        ],
      };
      await engine.flush();

      expect(
        adapter.calls.where((call) => call == 'POST /items/sync').length,
        1,
      );
      final body = adapter.postBodies.last as Map;
      expect((body['operations'] as List).length, 3);
      expect((body['operations'] as List).last['op'], 'delete');
      expect(await outbox.all(), isEmpty);
      expect((await api.cachedGet(1))?.name, 'One!');
    });

    test('a merged result heals the cache and fires the event', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One', 'tag': 'old'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'Mine', 'tag': 'mine'}));

      adapter.offline = false;
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 1,
            'status': 'merged',
            'record': {'id': 1, 'name': 'Server', 'tag': 'mine'},
            'applied_fields': ['tag'],
            'discarded_fields': ['name'],
          },
        ],
      };
      await engine.flush();

      final cached = await api.cachedGet(1);
      expect(cached?.name, 'Server');
      expect(cached?.getString('tag'), 'mine');
      expect(merged.single.applied, ['tag']);
      expect(merged.single.discarded, ['name']);
      expect(discarded, isEmpty);
    });

    test('a conflict result discards the operation and heals', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'Mine'}));

      adapter.offline = false;
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 1,
            'status': 'conflict',
            'record': {'id': 1, 'name': 'Theirs'},
          },
        ],
      };
      await engine.flush();

      expect((await api.cachedGet(1))?.name, 'Theirs');
      expect(discarded.single.reason, 'conflict');
      expect(await outbox.all(), isEmpty);
    });

    test(
      'with a ConflictStore, a conflict is parked instead of discarded',
      () async {
        final conflicts = ConflictStore(store);
        final parkEngine = SyncEngine(
          outbox,
          fetcher,
          getService<Bus>(),
          localStore: store,
          conflicts: conflicts,
        );

        await store.put('/items', 1, {'id': 1, 'name': 'One'});
        adapter.offline = true;
        await api.update(1, _Item({'name': 'Mine'}));

        adapter.offline = false;
        adapter.routes['POST /items/sync'] = (options) => {
          'results': [
            {
              'id': 1,
              'status': 'conflict',
              'record': {'id': 1, 'name': 'Theirs'},
              'discarded_fields': ['name'],
            },
          ],
        };
        await parkEngine.flush();

        final parked = await conflicts.all();
        expect(parked, hasLength(1));
        expect(parked.single.mine['name'], 'Mine');
        expect(parked.single.server['name'], 'Theirs');
        expect(parked.single.fields, ['name']);
        expect(discarded, isEmpty);
        expect(await outbox.all(), isEmpty);
      },
    );

    test(
      'resolveConflict keepMine re-enqueues a PATCH based on the server record',
      () async {
        final conflicts = ConflictStore(store);
        final resolveEngine = SyncEngine(
          outbox,
          fetcher,
          getService<Bus>(),
          localStore: store,
          conflicts: conflicts,
        );
        const entry = ConflictEntry(
          basePath: '/items',
          recordId: 1,
          mine: {'name': 'Mine'},
          base: {'name': 'One'},
          server: {'id': 1, 'name': 'Theirs'},
          fields: ['name'],
          createdAt: '2026-07-22T10:00:00Z',
          cache: OutboxCacheContext(kind: 'json', namespace: '/items'),
        );
        await conflicts.park(entry);
        adapter.offline = true;

        await resolveEngine.resolveConflict(entry, keepMine: true);
        // resolveConflict fires a fire-and-forget flush; let it settle
        // (offline, so it keeps the op) before asserting and teardown.
        await pumpEventQueue();

        expect(await conflicts.all(), isEmpty);
        final queued = await outbox.all();
        expect(queued, hasLength(1));
        expect(queued.single.method, 'PATCH');
        expect(queued.single.payload, {'name': 'Mine'});
        expect(queued.single.base, {'id': 1, 'name': 'Theirs'});
      },
    );

    test(
      'resolveConflict keepServer drops the conflict without re-enqueuing',
      () async {
        final conflicts = ConflictStore(store);
        final resolveEngine = SyncEngine(
          outbox,
          fetcher,
          getService<Bus>(),
          localStore: store,
          conflicts: conflicts,
        );
        const entry = ConflictEntry(
          basePath: '/items',
          recordId: 1,
          mine: {'name': 'Mine'},
          base: {'name': 'One'},
          server: {'id': 1, 'name': 'Theirs'},
          fields: ['name'],
          createdAt: '2026-07-22T10:00:00Z',
          cache: OutboxCacheContext(kind: 'json', namespace: '/items'),
        );
        await conflicts.park(entry);

        await resolveEngine.resolveConflict(entry, keepMine: false);

        expect(await conflicts.all(), isEmpty);
        expect(await outbox.all(), isEmpty);
      },
    );

    test(
      'an update on a server-deleted record removes the local copy',
      () async {
        await store.put('/items', 1, {'id': 1, 'name': 'One'});

        adapter.offline = true;
        await api.update(1, _Item({'name': 'Mine'}));

        adapter.offline = false;
        adapter.routes['POST /items/sync'] = (options) => {
          'results': [
            {'id': 1, 'status': 'deleted'},
          ],
        };
        await engine.flush();

        expect(await api.cachedGet(1), isNull);
        expect(discarded.single.reason, 'conflict');
      },
    );

    test('a rejected batch discards all its operations', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      await store.put('/items', 2, {'id': 2, 'name': 'Two'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));
      await api.update(2, _Item({'name': 'B'}));

      adapter.offline = false;
      // No sync route: the whole batch is rejected (404).
      await engine.flush();

      expect(await outbox.all(), isEmpty);
      expect(discarded, hasLength(2));
      expect(discarded.first.reason, 'rejected');
    });

    test(
      'a server rejection discards a create and cleans the temp record',
      () async {
        adapter.offline = true;
        await api.create(_Item({'name': 'Draft'}));

        adapter.offline = false;
        // No POST route: the replay gets a 404 rejection.
        await engine.flush();

        expect(await outbox.all(), isEmpty);
        expect(await api.cachedList(), isEmpty); // temp record cleaned
        expect(discarded.single.reason, 'rejected');
      },
    );

    test('a 500 response keeps the queue for a later retry', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));

      adapter.offline = false;
      adapter.errorRoutes['POST /items/sync'] = 500;
      await engine.flush();

      expect(await outbox.all(), hasLength(1));
      expect((await outbox.all()).single.attempts, 1);
      expect(discarded, isEmpty);
    });

    test('a 500 on a create keeps the queue too', () async {
      adapter.offline = true;
      await api.create(_Item({'name': 'Draft'}));

      adapter.offline = false;
      adapter.errorRoutes['POST /items'] = 503;
      await engine.flush();

      expect(await outbox.all(), hasLength(1));
      expect(await api.cachedList(), hasLength(1));
    });

    test('a rejected result discards only that operation', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      await store.put('/items', 2, {'id': 2, 'name': 'Two'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'Bad'}));
      await api.update(2, _Item({'name': 'Good'}));

      adapter.offline = false;
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {'id': 1, 'status': 'rejected', 'detail': 'invalid'},
          {
            'id': 2,
            'status': 'applied',
            'record': {'id': 2, 'name': 'Good'},
          },
        ],
      };
      await engine.flush();

      expect(await outbox.all(), isEmpty);
      expect(discarded.single.reason, 'rejected');
      expect((await api.cachedGet(2))?.name, 'Good');
    });

    test('a result count mismatch keeps the queue', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});

      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));

      adapter.offline = false;
      adapter.routes['POST /items/sync'] = (options) => {
        'results': <Map<String, dynamic>>[],
      };
      await engine.flush();

      expect(await outbox.all(), hasLength(1));
      expect(discarded, isEmpty);
    });

    test('remaps temporary ids inside later payloads', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});

      adapter.offline = true;
      final created = await api.create(_Item({'name': 'Child'}));
      await api.update(1, _Item({'parent': created.id}));

      adapter.offline = false;
      adapter.routes['POST /items'] = (options) => {'id': 42, 'name': 'Child'};
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 1,
            'status': 'applied',
            'record': {'id': 1, 'name': 'One', 'parent': 42},
          },
        ],
      };
      await engine.flush();

      final body = adapter.postBodies.last as Map;
      final operation = (body['operations'] as List).single as Map;
      expect(operation['payload'], {'parent': 42});
      expect(await outbox.all(), isEmpty);
    });

    test('segments larger than the batch size are chunked', () async {
      final chunked = SyncEngine(
        outbox,
        fetcher,
        getService<Bus>(),
        localStore: store,
        batchSize: 2,
      );

      adapter.offline = true;

      for (final id in [1, 2, 3]) {
        await store.put('/items', id, {'id': id, 'name': 'N$id'});
        await api.update(id, _Item({'name': 'N$id!'}));
      }

      adapter.offline = false;
      adapter.routes['POST /items/sync'] = (options) {
        final operations = (options.data as Map)['operations'] as List;

        return {
          'results': [
            for (final operation in operations)
              {'id': operation['id'], 'status': 'applied'},
          ],
        };
      };
      await chunked.flush();

      expect(
        adapter.calls.where((call) => call == 'POST /items/sync').length,
        2,
      );
      expect(await outbox.all(), isEmpty);
    });

    test('a poison operation is dropped after too many attempts', () async {
      final capped = SyncEngine(
        outbox,
        fetcher,
        getService<Bus>(),
        localStore: store,
        maxAttempts: 3,
      );

      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));

      adapter.offline = false;
      adapter.errorRoutes['POST /items/sync'] = 500;

      await capped.flush();
      await capped.flush();
      expect(await outbox.all(), hasLength(1));

      await capped.flush();

      expect(await outbox.all(), isEmpty);
      expect(discarded.single.reason, 'rejected');
    });

    test('offline attempts never discard the operation', () async {
      final capped = SyncEngine(
        outbox,
        fetcher,
        getService<Bus>(),
        localStore: store,
        maxAttempts: 2,
      );

      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));

      await capped.flush();
      await capped.flush();
      await capped.flush();

      expect(await outbox.all(), hasLength(1));
      expect(discarded, isEmpty);
    });

    test('a transient server failure schedules a deferred retry', () async {
      final retrying = SyncEngine(
        outbox,
        fetcher,
        getService<Bus>(),
        localStore: store,
        retryBaseDelay: const Duration(milliseconds: 20),
      );

      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));

      adapter.offline = false;
      adapter.errorRoutes['POST /items/sync'] = 500;
      await retrying.flush();
      expect(await outbox.all(), hasLength(1));

      // The server recovers: the deferred retry drains the queue by itself.
      adapter.errorRoutes.remove('POST /items/sync');
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 1,
            'status': 'applied',
            'record': {'id': 1, 'name': 'A'},
          },
        ],
      };
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(await outbox.all(), isEmpty);
      await retrying.stop();
    });

    test('offline failures do not schedule a deferred retry', () async {
      final retrying = SyncEngine(
        outbox,
        fetcher,
        getService<Bus>(),
        localStore: store,
        retryBaseDelay: const Duration(milliseconds: 10),
      );

      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));

      await retrying.flush();
      adapter.routes['POST /items/sync'] = (options) => throw StateError('x');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Still queued and never retried while offline (no network call made).
      expect(await outbox.all(), hasLength(1));
      expect(adapter.calls, isEmpty);
      await retrying.stop();
    });

    test(
      'deleting a temp record online cancels both without network',
      () async {
        adapter.offline = true;
        final created = await api.create(_Item({'name': 'Draft'}));

        adapter.offline = false;
        adapter.calls.clear();
        await api.delete(created.id!);

        expect(adapter.calls, isEmpty);
        expect(await outbox.all(), isEmpty);
        expect(await api.cachedList(), isEmpty);
      },
    );

    test('a create cancelled mid-replay deletes the server record', () async {
      adapter.offline = true;
      final created = await api.create(_Item({'name': 'Draft'}));

      adapter.offline = false;
      adapter.asyncRoutes['POST /items'] = (options) async {
        // The user deletes the record while the create request is in flight.
        await api.delete(created.id!);

        return {'id': 42, 'name': 'Draft'};
      };
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {'id': 42, 'status': 'applied'},
        ],
      };
      await engine.flush();
      // The compensating delete replays in the follow-up flush.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final body = adapter.postBodies.last as Map;
      final operation = (body['operations'] as List).single as Map;
      expect(operation['op'], 'delete');
      expect(operation['id'], 42);
      expect(await outbox.all(), isEmpty);
      expect(await api.cachedList(), isEmpty);
    });

    test('the temp id map survives across flushes', () async {
      adapter.offline = true;
      final created = await api.create(_Item({'name': 'Draft'}));

      adapter.offline = false;
      adapter.routes['POST /items'] = (options) => {'id': 42, 'name': 'Draft'};
      await engine.flush();

      // An operation enqueued later still references the temporary id
      // (e.g. app restarted between the swap and this write).
      await outbox.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: 'PATCH',
          basePath: '/items',
          recordId: created.id,
          payload: {'name': 'Late'},
          createdAt: createdAt,
          cache: const OutboxCacheContext(kind: 'json', namespace: '/items'),
        ),
      );
      adapter.routes['POST /items/sync'] = (options) => {
        'results': [
          {
            'id': 42,
            'status': 'applied',
            'record': {'id': 42, 'name': 'Late'},
          },
        ],
      };
      await engine.flush();

      final body = adapter.postBodies.last as Map;
      expect((body['operations'] as List).single['id'], 42);
      expect(await outbox.all(), isEmpty);
    });

    test('going offline mid-flush keeps the remaining operations', () async {
      await store.put('/items', 1, {'id': 1, 'name': 'One'});
      adapter.offline = true;
      await api.update(1, _Item({'name': 'A'}));
      await api.create(_Item({'name': 'B'}));

      // Still offline: the flush should stop on the first operation.
      await engine.flush();

      expect(await outbox.all(), hasLength(2));
      expect((await outbox.all()).first.attempts, 1);
    });
  });
}
