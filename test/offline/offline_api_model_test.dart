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

/// Minimal metadata provider so `modelName`-based APIs resolve their path
/// (`item` → api_name `items`).
class _FakeMetadataProvider implements MetadataProvider {
  final Map<String, MetadataModel> _map;

  _FakeMetadataProvider(this._map);

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
  void setPrefix(String? newPrefix) {}
}

class _Item extends BaseModel<_Item> {
  _Item(super.data);

  String get name => getString('name') ?? '';
}

class _ItemApi extends ApiModel<_Item> {
  _ItemApi({
    required Fetcher fetcher,
    required LocalStore localStore,
    Outbox? outbox,
    String basePath = '/items',
  }) : super(
         basePath,
         fetcher: fetcher,
         offlineBindings: OfflineStores(localStore: localStore, outbox: outbox),
       );

  @override
  List<String>? get syncFields => const ['id', 'name', 'tag'];

  @override
  int get syncPageSize => 2;

  @override
  _Item fromJson(Map<String, dynamic> json) => _Item(json);
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function(RequestOptions options)>
  routes = {};
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
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

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, {
  int? total,
  int offset = 0,
}) => {
  'items': items,
  'total': total ?? items.length,
  'limit': items.length,
  'offset': offset,
  'total_pages': 1,
};

/// Serve [all] as a paginated collection honoring limit/offset params and
/// an `X-Filter: ["id","in",[...]]` header (the sync fetch phase).
Map<String, dynamic> Function(RequestOptions) _paginated(
  List<Map<String, dynamic>> all,
) {
  return (options) {
    var data = all;
    final filterHeader = options.headers['X-Filter'];

    if (filterHeader is String && filterHeader.isNotEmpty) {
      final filter = jsonDecode(filterHeader);

      if (filter is List &&
          filter.length == 3 &&
          filter[0] == 'id' &&
          filter[1] == 'in') {
        final ids = (filter[2] as List).toSet();
        data = all.where((record) => ids.contains(record['id'])).toList();
      }
    }

    final offset = int.tryParse('${options.queryParameters['offset']}') ?? 0;
    final limit =
        int.tryParse('${options.queryParameters['limit']}') ?? data.length;
    final end = offset + limit > data.length ? data.length : offset + limit;
    final items = offset >= data.length
        ? <Map<String, dynamic>>[]
        : data.sublist(offset, end);

    return _page(items, total: data.length, offset: offset);
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late Fetcher fetcher;
  late _ItemApi api;

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
        _FakeMetadataProvider({
          'item': const MetadataModel(
            name: 'item',
            apiName: 'items',
            label: 'Item',
            labelPlural: 'Items',
            searchable: false,
            sortable: false,
            synchronizable: true,
            fields: {},
          ),
        }),
      );
    }
  });

  setUp(() async {
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
    api = _ItemApi(fetcher: fetcher, localStore: store);
  });

  tearDown(() => store.close());

  group('sync with pending outbox writes', () {
    late Outbox outbox;
    late _ItemApi bufferedApi;

    setUp(() {
      outbox = Outbox(store);
      bufferedApi = _ItemApi(
        fetcher: fetcher,
        localStore: store,
        outbox: outbox,
      );
    });

    test('re-applies pending optimistic updates over pulled records', () async {
      await store.put('/items', 1, {
        'id': 1,
        'name': 'One',
        'updated_at': 't1',
      });

      adapter.offline = true;
      await bufferedApi.update(1, _Item({'name': 'Mine'}));

      adapter.offline = false;
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'Server', 'tag': 'fresh', 'updated_at': 't2'},
      ]);
      await bufferedApi.sync();

      final cached = await bufferedApi.cachedGet(1);
      expect(cached?.name, 'Mine');
      expect(cached?.getString('tag'), 'fresh');
      expect(await outbox.all(), hasLength(1));
    });

    test('keeps records with pending writes missing from the server', () async {
      await store.put('/items', 2, {
        'id': 2,
        'name': 'Two',
        'updated_at': 't1',
      });

      adapter.offline = true;
      await bufferedApi.update(2, _Item({'name': 'Kept'}));

      adapter.offline = false;
      adapter.routes['GET /items'] = _paginated([]);
      await bufferedApi.sync();

      expect((await bufferedApi.cachedGet(2))?.name, 'Kept');
    });

    test('operations are enqueued with the unresolved path and the captured '
        'context', () async {
      final tenant = _TenantResolver()..slug = 'ws-a';
      if (!hasService<OfflineContextParams>()) {
        container.registerSingleton<OfflineContextParams>(
          OfflineContextParams(),
        );
      }
      getService<OfflineContextParams>().register(tenant);
      addTearDown(() => getService<OfflineContextParams>().unregister(tenant));

      final scoped = _ItemApi(
        fetcher: fetcher,
        localStore: store,
        outbox: outbox,
        basePath: '/{workspace}/items',
      );

      adapter.offline = true;
      await scoped.update(1, _Item({'name': 'Mine'}));

      final operation = (await outbox.all()).single;
      expect(operation.basePath, '/{workspace}/items');
      expect(operation.context, {'workspace': 'ws-a'});
    });

    test('sync only considers pending writes of its own context', () async {
      final tenant = _TenantResolver()..slug = 'ws-a';
      if (!hasService<OfflineContextParams>()) {
        container.registerSingleton<OfflineContextParams>(
          OfflineContextParams(),
        );
      }
      getService<OfflineContextParams>().register(tenant);
      addTearDown(() => getService<OfflineContextParams>().unregister(tenant));

      final scoped = _ItemApi(
        fetcher: fetcher,
        localStore: store,
        outbox: outbox,
        basePath: '/{workspace}/items',
      );

      // A pending delete buffered under ws-a for record 9.
      adapter.offline = true;
      await scoped.delete(9);

      // The same record pulled while ws-b is current: ws-a's pending delete
      // must NOT be replayed over it.
      tenant.slug = 'ws-b';
      adapter.offline = false;
      adapter.routes['GET /{workspace}/items'] = _paginated([
        {'id': 9, 'name': 'Nine', 'updated_at': 't2'},
      ]);
      await scoped.sync();

      expect((await scoped.cachedGet(9))?.name, 'Nine');
      expect(await outbox.all(), hasLength(1));
    });

    test('applies pending deletes over pulled records', () async {
      await store.put('/items', 3, {
        'id': 3,
        'name': 'Three',
        'updated_at': 't1',
      });

      adapter.offline = true;
      await bufferedApi.delete(3);

      adapter.offline = false;
      adapter.routes['GET /items'] = _paginated([
        {'id': 3, 'name': 'Three', 'updated_at': 't2'},
      ]);
      await bufferedApi.sync();

      expect(await bufferedApi.cachedGet(3), isNull);
      expect(await outbox.all(), hasLength(1));
    });
  });

  group('ApiModel.sync', () {
    test('mirrors the whole collection by auto-paginating', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
        {'id': 3, 'name': 'Three'},
        {'id': 4, 'name': 'Four'},
        {'id': 5, 'name': 'Five'},
      ]);

      await api.sync();

      expect(await api.cachedList(), hasLength(5));
      // Manifest walked by pages of 2 (3 calls), then 3 id-batches fetched.
      expect(adapter.callCount, 6);
    });

    test('an unchanged collection costs only the manifest walk', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One', 'updated_at': '2020-01-01T00:00:00'},
        {'id': 2, 'name': 'Two', 'updated_at': '2020-01-01T00:00:00'},
      ]);

      await api.sync();
      final afterFirst = adapter.callCount;

      await api.sync();

      // Second sync: manifest only (1 page), nothing to fetch.
      expect(adapter.callCount, afterFirst + 1);
      expect(await api.cachedList(), hasLength(2));
    });

    test('pending offline records survive the sync pruning', () async {
      await store.put('/items', -5, {
        'id': -5,
        'name': 'Draft',
        '_offline_pending': true,
      });
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
      ]);

      await api.sync();

      expect(await api.cachedGet(-5), isNotNull);
      expect(await api.cachedList(), hasLength(2));
    });

    test('prunes records deleted on the server', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
      ]);
      await api.sync();

      adapter.routes['GET /items'] = _paginated([
        {'id': 2, 'name': 'Two'},
      ]);
      await api.sync();

      final cached = await api.cachedList();

      expect(cached, hasLength(1));
      expect(cached.single.id, 2);
    });
  });

  group('ApiModel.list', () {
    test('merges fetched records into the cache without pruning', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
        {'id': 3, 'name': 'Three'},
      ]);
      await api.sync();

      // A partial page (limit 1) must not prune the other cached records.
      await api.list(query: const ListQuery(limit: 1));

      expect(await api.cachedList(), hasLength(3));
    });

    test(
      'deep-merges records so a narrow selection keeps cached fields',
      () async {
        adapter.routes['GET /items'] = _paginated([
          {'id': 1, 'name': 'One', 'tag': 'keep'},
        ]);
        await api.sync();

        adapter.routes['GET /items'] = (options) => _page([
          {'id': 1, 'name': 'Renamed'},
        ]);
        await api.list();

        final cached = await api.cachedGet(1);

        expect(cached?.name, 'Renamed');
        expect(cached?.getString('tag'), 'keep');
      },
    );

    test('evaluates the query locally when offline', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'Bravo'},
        {'id': 2, 'name': 'Alpha'},
        {'id': 3, 'name': 'Charlie'},
      ]);
      await api.sync();

      adapter.offline = true;
      final result = await api.list(
        query: const ListQuery(orderBy: 'name', limit: 2, offset: 1),
      );

      expect(result.items.map((item) => item.name), ['Bravo', 'Charlie']);
      expect(result.total, 3);
      expect(result.offset, 1);
    });

    test(
      'serves the unfiltered collection for a filtered query offline',
      () async {
        adapter.routes['GET /items'] = _paginated([
          {'id': 1, 'name': 'One'},
          {'id': 2, 'name': 'Two'},
        ]);
        await api.sync();

        adapter.offline = true;
        final result = await api.list(
          query: const ListQuery(filter: ['name', '=', 'One']),
        );

        expect(result.items, hasLength(2));
      },
    );

    test('rethrows offline errors when the cache is empty', () async {
      adapter.offline = true;

      await expectLater(api.list(), throwsA(isA<NetworkError>()));
    });

    test('rethrows server errors without falling back to the cache', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
      ]);
      await api.sync();

      adapter.routes.clear();

      await expectLater(
        api.list(),
        throwsA(
          isA<HttpError>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('ApiModel.cachedQuery', () {
    test('applies order_by desc and pagination locally', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'Bravo'},
        {'id': 2, 'name': 'Alpha'},
        {'id': 3, 'name': 'Charlie'},
      ]);
      await api.sync();

      final result = await api.cachedQuery(
        const ListQuery(orderBy: 'name:desc', page: 1, size: 2),
      );

      expect(result.items.map((item) => item.name), ['Charlie', 'Bravo']);
      expect(result.total, 3);
      expect(result.totalPages, 2);
    });
  });

  group('ApiModel.get', () {
    test('serves the cached record when offline', () async {
      adapter.routes['GET /items/1'] = (options) => {'id': 1, 'name': 'One'};
      await api.get(1);

      adapter.offline = true;
      final item = await api.get(1);

      expect(item.name, 'One');
    });

    test('rethrows offline errors for uncached records', () async {
      adapter.offline = true;

      await expectLater(api.get(1), throwsA(isA<NetworkError>()));
    });
  });

  group('ApiModel writes', () {
    test('create adds the record to the cache', () async {
      adapter.routes['POST /items'] = (options) => {'id': 3, 'name': 'Three'};

      await api.create(_Item({'name': 'Three'}));

      expect(await store.get('/items', 3), isNotNull);
    });

    test('update deep-merges the cached record', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One', 'tag': 'keep'},
      ]);
      await api.sync();

      adapter.routes['PATCH /items/1'] = (options) => {
        'id': 1,
        'name': 'Renamed',
      };
      await api.update(1, _Item({'name': 'Renamed'}));

      final cached = await api.cachedGet(1);

      expect(cached?.name, 'Renamed');
      expect(cached?.getString('tag'), 'keep');
    });

    test('delete removes the cached record', () async {
      adapter.routes['GET /items/1'] = (options) => {'id': 1, 'name': 'One'};
      await api.get(1);

      adapter.routes['DELETE /items/1'] = (options) => {};
      await api.delete(1);

      expect(await api.cachedGet(1), isNull);
    });
  });

  group('ApiModel.listCacheThenNetwork', () {
    test('emits the local evaluation first, then the fresh result', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
      ]);
      await api.sync();

      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
      ]);

      final emissions = await api.listCacheThenNetwork().toList();

      expect(emissions, hasLength(2));
      expect(emissions.first.items, hasLength(1));
      expect(emissions.last.items, hasLength(2));
    });

    test('stays silent offline once the cache has been emitted', () async {
      adapter.routes['GET /items'] = _paginated([
        {'id': 1, 'name': 'One'},
      ]);
      await api.sync();

      adapter.offline = true;
      final emissions = await api.listCacheThenNetwork().toList();

      expect(emissions.single.items, hasLength(1));
    });

    test('surfaces offline errors when nothing is cached', () async {
      adapter.offline = true;

      await expectLater(
        api.listCacheThenNetwork().toList(),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('ApiModel replicated mode', replicatedModeTests);
}

class _TenantResolver implements OfflineContextParamsResolver {
  String? slug = 'acme';

  @override
  Map<String, Object?> resolve() => {'workspace': slug};
}

/// Test double of the app-side prefix interceptor: request substitution is
/// the app's job, the framework only carries the offline context.
class _TenantPrefixInterceptor extends Interceptor {
  final _TenantResolver tenant;

  _TenantPrefixInterceptor(this.tenant);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final slug = tenant.slug;

    if (slug != null && options.path.contains('/{workspace}')) {
      options.path = options.path.replaceAll('/{workspace}', '/$slug');
    }

    handler.next(options);
  }
}

class _ReplicatedItemApi extends ApiModel<_Item> {
  _ReplicatedItemApi({
    required Fetcher fetcher,
    required Replica replica,
    required LocalStore localStore,
  }) : super(
         '/{workspace}',
         modelName: 'item',
         fetcher: fetcher,
         offlineBindings: OfflineStores(
           localStore: localStore,
           replica: replica,
         ),
       );

  @override
  List<String>? get syncFields => const ['id', 'name', 'tag', 'qty'];

  @override
  int get syncPageSize => 2;

  @override
  _Item fromJson(Map<String, dynamic> json) => _Item(json);
}

const _itemSchema = LocalSchema({
  'item': LocalModelSchema(
    name: 'item',
    apiName: 'items',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'tag': LocalFieldSchema(name: 'tag', type: 'char'),
      'qty': LocalFieldSchema(name: 'qty', type: 'integer'),
    },
  ),
});

void replicatedModeTests() {
  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late ReplicaStore replicaStore;
  late Replica replica;
  late _ReplicatedItemApi api;
  late _TenantResolver tenant;

  Fetcher fetcher() => Fetcher.create(
    dio: Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter,
    bus: getService<Bus>(),
    customInterceptors: [
      InterceptorConfig(_TenantPrefixInterceptor(tenant), priority: 100),
    ],
    enableAuth: false,
    enableTimezone: false,
    enableRefreshToken: false,
    enableConnectionRetry: false,
    enableLogging: false,
    enableErrorTransform: false,
  );

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    adapter = _ScriptedAdapter();
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    replicaStore = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    await replicaStore.open();
    replica = Replica.withSchema(replicaStore, _itemSchema);
    tenant = _TenantResolver();
    if (!hasService<OfflineContextParams>()) {
      container.registerSingleton<OfflineContextParams>(OfflineContextParams());
    }
    getService<OfflineContextParams>().register(tenant);
    api = _ReplicatedItemApi(
      fetcher: fetcher(),
      replica: replica,
      localStore: store,
    );
  });

  tearDown(() async {
    getService<OfflineContextParams>().unregister(tenant);
    await store.close();
    await replicaStore.close();
  });

  test('cached reads on a never-synced model create the table', () async {
    // Regression: a fresh replica database (first install, purge) must not
    // crash the cached reads called before the first sync.
    expect(await api.cachedList(), isEmpty);
    expect(await api.cachedGet(1), isNull);
  });

  test('a broken replica database degrades instead of crashing', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'One', 'qty': 3},
    ]);
    await api.sync();
    expect(await api.cachedList(), hasLength(1));

    // Kill the replica database mid-session: every replica access throws
    // from now on.
    await replicaStore.close();

    // Cached reads degrade to the fallback cache (empty here) instead of
    // throwing…
    expect(await api.cachedList(), isEmpty);
    expect(await api.cachedGet(1), isNull);

    // …and network reads still succeed, skipping the broken mirroring.
    final result = await api.list();
    expect(result.items, hasLength(1));
    expect(result.items.single.name, 'One');
  });

  test('sync mirrors the collection into the scoped replica table', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'One', 'qty': 3},
      {'id': 2, 'name': 'Two', 'qty': 8},
      {'id': 3, 'name': 'Three', 'qty': 12},
    ]);

    await api.sync();

    expect(await replicaStore.getAll('item', 'acme'), hasLength(3));
    expect(await replicaStore.getAll('item', 'globex'), isEmpty);
  });

  test('scopes are isolated per workspace', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'Acme item', 'qty': 1},
    ]);
    await api.sync();

    tenant.slug = 'globex';
    adapter.routes['GET /globex/items'] = _paginated([
      {'id': 9, 'name': 'Globex item', 'qty': 2},
    ]);
    await api.sync();

    expect((await api.cachedList()).single.name, 'Globex item');
    tenant.slug = 'acme';
    expect((await api.cachedList()).single.name, 'Acme item');
  });

  test('offline queries evaluate filters with server parity', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'Bravo', 'qty': 3},
      {'id': 2, 'name': 'Alpha', 'qty': 8},
      {'id': 3, 'name': 'Charlie', 'qty': 12},
    ]);
    await api.sync();

    adapter.offline = true;
    final result = await api.list(
      query: const ListQuery(
        filter: ['qty', '>', 5],
        orderBy: 'name:desc',
        limit: 1,
      ),
    );

    expect(result.items.single.name, 'Charlie');
    expect(result.total, 2);
  });

  test(
    'a filtered empty result does not rethrow once the scope is synced',
    () async {
      adapter.routes['GET /acme/items'] = _paginated([
        {'id': 1, 'name': 'One', 'qty': 3},
      ]);
      await api.sync();

      adapter.offline = true;
      final result = await api.list(
        query: const ListQuery(filter: ['qty', '>', 99]),
      );

      expect(result.items, isEmpty);
      expect(result.total, 0);
    },
  );

  test('an unsynced scope rethrows offline errors', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'One', 'qty': 3},
    ]);
    await api.sync();

    tenant.slug = 'globex';
    adapter.offline = true;

    await expectLater(api.list(), throwsA(isA<NetworkError>()));
  });

  test('list deep-merges records without pruning the scope', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'One', 'tag': 'keep', 'qty': 3},
      {'id': 2, 'name': 'Two', 'qty': 8},
    ]);
    await api.sync();

    adapter.routes['GET /acme/items'] = (options) => _page([
      {'id': 1, 'name': 'Renamed'},
    ]);
    await api.list(query: const ListQuery(limit: 1));

    expect(await api.cachedList(), hasLength(2));
    final merged = await api.cachedGet(1);
    expect(merged?.name, 'Renamed');
    expect(merged?.getString('tag'), 'keep');
  });

  test('update and delete are routed to the replica scope', () async {
    adapter.routes['GET /acme/items'] = _paginated([
      {'id': 1, 'name': 'One', 'qty': 3},
    ]);
    await api.sync();

    adapter.routes['PATCH /acme/items/1'] = (options) => {
      'id': 1,
      'name': 'Patched',
    };
    await api.update(1, _Item({'name': 'Patched'}));
    expect((await api.cachedGet(1))?.name, 'Patched');

    adapter.routes['DELETE /acme/items/1'] = (options) => {};
    await api.delete(1);
    expect(await api.cachedGet(1), isNull);
  });
}
