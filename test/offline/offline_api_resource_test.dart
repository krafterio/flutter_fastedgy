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

class _Profile extends BaseModel<_Profile> {
  _Profile(super.data);

  String get name => getString('name') ?? '';
}

class _ProfileApi extends OfflineApiResource {
  _ProfileApi({required Fetcher fetcher, required LocalStore localStore})
    : super('/profile', fetcher: fetcher, localStore: localStore);

  Future<_Profile> getProfile() => remoteOrCached(
    _Profile.new,
    () async =>
        _Profile((await fetcher.get(basePath)).data as Map<String, dynamic>),
  );

  Stream<_Profile> watchProfile() => cacheThenRemote(
    _Profile.new,
    () async =>
        _Profile((await fetcher.get(basePath)).data as Map<String, dynamic>),
  );
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function()> routes = {};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late _ProfileApi api;

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
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    api = _ProfileApi(fetcher: fetcher, localStore: store);
  });

  tearDown(() => store.close());

  group('OfflineApiResource.remoteOrCached', () {
    test('caches the remote result under the default slot', () async {
      adapter.routes['GET /profile'] = () => {'id': 1, 'name': 'Ada'};

      await api.getProfile();

      expect((await api.cachedRecord(_Profile.new))?.name, 'Ada');
    });

    test('serves the cache when offline', () async {
      adapter.routes['GET /profile'] = () => {'id': 1, 'name': 'Ada'};
      await api.getProfile();

      adapter.offline = true;
      final profile = await api.getProfile();

      expect(profile.name, 'Ada');
    });

    test('rethrows offline errors when nothing is cached', () async {
      adapter.offline = true;

      await expectLater(api.getProfile(), throwsA(isA<NetworkError>()));
    });

    test('rethrows server errors without falling back to the cache', () async {
      adapter.routes['GET /profile'] = () => {'id': 1, 'name': 'Ada'};
      await api.getProfile();

      adapter.routes.clear();

      await expectLater(
        api.getProfile(),
        throwsA(
          isA<HttpError>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('OfflineApiResource cache primitives', () {
    test('stores several records under explicit keys', () async {
      await api.cacheRecord(_Profile({'id': 1, 'name': 'Ada'}));
      await api.cacheRecord(
        _Profile({'id': 2, 'name': 'Dark'}),
        key: 'settings',
      );

      expect((await api.cachedRecord(_Profile.new))?.name, 'Ada');
      expect(
        (await api.cachedRecord(_Profile.new, key: 'settings'))?.name,
        'Dark',
      );
    });

    test('removeCachedRecord removes a single key', () async {
      await api.cacheRecord(_Profile({'id': 1}));
      await api.cacheRecord(_Profile({'id': 2}), key: 'settings');

      await api.removeCachedRecord();

      expect(await api.cachedRecord(_Profile.new), isNull);
      expect(await api.cachedRecord(_Profile.new, key: 'settings'), isNotNull);
    });

    test('clearCache removes every key of the resource', () async {
      await api.cacheRecord(_Profile({'id': 1}));
      await api.cacheRecord(_Profile({'id': 2}), key: 'settings');

      await api.clearCache();

      expect(await api.cachedRecord(_Profile.new), isNull);
      expect(await api.cachedRecord(_Profile.new, key: 'settings'), isNull);
    });
  });

  group('OfflineApiResource.cacheThenRemote', () {
    test('emits the cache first, then the fresh record', () async {
      adapter.routes['GET /profile'] = () => {'id': 1, 'name': 'Ada'};
      await api.getProfile();

      adapter.routes['GET /profile'] = () => {'id': 1, 'name': 'Grace'};
      final emissions = await api.watchProfile().toList();

      expect(emissions, hasLength(2));
      expect(emissions.first.name, 'Ada');
      expect(emissions.last.name, 'Grace');
    });

    test('stays silent offline once the cache has been emitted', () async {
      adapter.routes['GET /profile'] = () => {'id': 1, 'name': 'Ada'};
      await api.getProfile();

      adapter.offline = true;
      final emissions = await api.watchProfile().toList();

      expect(emissions.single.name, 'Ada');
    });

    test('surfaces offline errors when nothing is cached', () async {
      adapter.offline = true;

      await expectLater(
        api.watchProfile().toList(),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
