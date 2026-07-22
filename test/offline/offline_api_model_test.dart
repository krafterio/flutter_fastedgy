/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _Item extends BaseModel<_Item> {
  _Item(super.data);

  String get name => getString('name') ?? '';
}

class _ItemApi extends OfflineApiModel<_Item> {
  _ItemApi({required Fetcher fetcher, required LocalStore localStore})
    : super('/items', fetcher: fetcher, localStore: localStore);

  @override
  dynamic get syncFields => 'id,name,tag';

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

/// Serve [all] as a paginated collection honoring limit/offset params.
Map<String, dynamic> Function(RequestOptions) _paginated(
  List<Map<String, dynamic>> all,
) {
  return (options) {
    final offset = int.tryParse('${options.queryParameters['offset']}') ?? 0;
    final limit =
        int.tryParse('${options.queryParameters['limit']}') ?? all.length;
    final end = offset + limit > all.length ? all.length : offset + limit;
    final items = offset >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(offset, end);

    return _page(items, total: all.length, offset: offset);
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late SembastLocalStore store;
  late _ItemApi api;
  var dbIndex = 0;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() async {
    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.httpClientAdapter = adapter;
    final fetcher = Fetcher.create(
      dio: dio,
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
      enableErrorTransform: false,
    );
    store = SembastLocalStore(
      databaseOpener: () =>
          newDatabaseFactoryMemory().openDatabase('test_${dbIndex++}.db'),
    );
    await store.open();
    api = _ItemApi(fetcher: fetcher, localStore: store);
  });

  tearDown(() => store.close());

  group('OfflineApiModel.sync', () {
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
      expect(adapter.callCount, 3); // 5 records walked by pages of 2
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

  group('OfflineApiModel.list', () {
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

  group('OfflineApiModel.cachedQuery', () {
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

  group('OfflineApiModel.get', () {
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

  group('OfflineApiModel writes', () {
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

  group('OfflineApiModel.listCacheThenNetwork', () {
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
}
