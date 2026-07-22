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
  _Item fromJson(Map<String, dynamic> json) => _Item(json);
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function()> routes = {};
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
      jsonEncode(handler()),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'limit': 50,
  'offset': 0,
  'total_pages': 1,
};

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

  group('OfflineApiModel.list', () {
    test('caches fetched records', () async {
      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
      ]);

      await api.list();

      expect(await store.getAll('/items'), hasLength(2));
    });

    test('prunes server-side deletions on a complete refetch', () async {
      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
      ]);
      await api.list();

      adapter.routes['GET /items'] = () => _page([
        {'id': 2, 'name': 'Two'},
      ]);
      await api.list();

      final cached = await api.cachedList();

      expect(cached, hasLength(1));
      expect(cached.single.id, 2);
    });

    test('serves the cache when offline', () async {
      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
      ]);
      await api.list();

      adapter.offline = true;
      final result = await api.list();

      expect(result.items, hasLength(1));
      expect(result.items.single.name, 'One');
    });

    test('rethrows offline errors when the cache is empty', () async {
      adapter.offline = true;

      await expectLater(api.list(), throwsA(isA<NetworkError>()));
    });

    test('rethrows server errors without falling back to the cache', () async {
      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
      ]);
      await api.list();

      adapter.routes.clear();

      await expectLater(
        api.list(),
        throwsA(
          isA<HttpError>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('OfflineApiModel.get', () {
    test('serves the cached record when offline', () async {
      adapter.routes['GET /items/1'] = () => {'id': 1, 'name': 'One'};
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
      adapter.routes['POST /items'] = () => {'id': 3, 'name': 'Three'};

      await api.create(_Item({'name': 'Three'}));

      expect(await store.get('/items', 3), isNotNull);
    });

    test('update refreshes the cached record', () async {
      adapter.routes['GET /items/1'] = () => {'id': 1, 'name': 'One'};
      await api.get(1);

      adapter.routes['PATCH /items/1'] = () => {'id': 1, 'name': 'Renamed'};
      await api.update(1, _Item({'name': 'Renamed'}));

      expect((await api.cachedGet(1))?.name, 'Renamed');
    });

    test('delete removes the cached record', () async {
      adapter.routes['GET /items/1'] = () => {'id': 1, 'name': 'One'};
      await api.get(1);

      adapter.routes['DELETE /items/1'] = () => {};
      await api.delete(1);

      expect(await api.cachedGet(1), isNull);
    });
  });

  group('OfflineApiModel.listCacheThenNetwork', () {
    test('emits the cache first, then the fresh result', () async {
      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
      ]);
      await api.list();

      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
        {'id': 2, 'name': 'Two'},
      ]);

      final emissions = await api.listCacheThenNetwork().toList();

      expect(emissions, hasLength(2));
      expect(emissions.first.items, hasLength(1));
      expect(emissions.last.items, hasLength(2));
    });

    test('stays silent offline once the cache has been emitted', () async {
      adapter.routes['GET /items'] = () => _page([
        {'id': 1, 'name': 'One'},
      ]);
      await api.list();

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
