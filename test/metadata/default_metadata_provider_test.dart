/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _MockAuthProvider implements AuthProvider {
  @override
  Future<bool> isAuthenticated() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _AcmeWorkspace implements OfflineContextParamsResolver {
  @override
  Map<String, Object?> resolve() => const {'workspace': 'acme'};
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function(RequestOptions options)>
  routes = {};

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

const _metadatasPayload = {
  'workspace_user': {
    'name': 'workspace_user',
    'api_name': 'workspace_users',
    'label': 'Workspace user',
    'label_plural': 'Workspace users',
    'searchable': false,
    'sortable': false,
    'sortable_field': null,
    'fields': {
      'role': {
        'name': 'role',
        'label': 'Role',
        'type': 'choice',
        'readonly': false,
        'required': false,
        'searchable': false,
        'extra': false,
        'filter_operators': <String>[],
        'target': null,
        'targets': null,
        'choices': {'ADMIN': 'Admin', 'MEMBER': 'Member'},
      },
    },
  },
};

Fetcher _fetcher(_ScriptedAdapter adapter) => Fetcher.create(
  dio: Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..httpClientAdapter = adapter,
  bus: getService<Bus>(),
  enableAuth: false,
  enableTimezone: false,
  enableRefreshToken: false,
  enableConnectionRetry: false,
  enableLogging: false,
  enableErrorTransform: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late DefaultMetadataProvider provider;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() async {
    adapter = _ScriptedAdapter();
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();

    if (hasService<LocalStore>()) {
      container.unregister<LocalStore>();
    }
    container.registerSingleton<LocalStore>(store);

    provider = DefaultMetadataProvider(
      _fetcher(adapter),
      _MockAuthProvider(),
      getService<Bus>(),
    );
  });

  tearDown(() async {
    container.unregister<LocalStore>();
    await store.close();
  });

  group('DefaultMetadataProvider offline mirror', () {
    test('persists fetched metadata into the local store', () async {
      adapter.routes['GET /dataset/metadatas'] = (options) => _metadatasPayload;

      final metadatas = await provider.getMetadatas();

      expect(metadatas?['workspace_user']?.apiName, 'workspace_users');
      expect(await store.get('/dataset/metadatas', 'metadatas'), isNotNull);
    });

    test('serves the mirrored metadata when offline', () async {
      adapter.routes['GET /dataset/metadatas'] = (options) => _metadatasPayload;
      await provider.getMetadatas();

      adapter.offline = true;
      final offlineProvider = DefaultMetadataProvider(
        _fetcher(adapter),
        _MockAuthProvider(),
        getService<Bus>(),
      );

      final metadatas = await offlineProvider.getMetadatas();

      expect(metadatas?['workspace_user']?.fields['role']?.choices, {
        'ADMIN': 'Admin',
        'MEMBER': 'Member',
      });
    });

    test('reports the error when offline with no mirror', () async {
      adapter.offline = true;

      final metadatas = await provider.getMetadatas();

      expect(metadatas, isNull);
      expect(provider.error, isNotNull);
    });
  });

  group('DefaultMetadataProvider single-flight', () {
    test('serves concurrent callers from one request', () async {
      var calls = 0;
      adapter.routes['GET /dataset/metadatas'] = (options) {
        calls++;

        return _metadatasPayload;
      };

      final results = await Future.wait([
        provider.getMetadatas(),
        provider.getMetadatas(),
        provider.getMetadatas(),
      ]);

      expect(calls, 1);
      for (final metadatas in results) {
        expect(metadatas?['workspace_user']?.apiName, 'workspace_users');
      }
    });

    test('stays silent while the tenant is unresolved', () async {
      var calls = 0;
      adapter.routes['GET /dataset/metadatas'] = (options) {
        calls++;

        return _metadatasPayload;
      };

      // A tenant-scoped prefix with nothing to resolve it: asking now would
      // only reach a route that does not exist, so nothing is requested.
      provider.setPrefix('/{workspace}');

      expect(await provider.getMetadatas(), isNull);
      expect(calls, 0);
    });

    test('fetches under the tenant once it resolves', () async {
      var scoped = 0;
      adapter.routes['GET /acme/dataset/metadatas'] = (options) {
        scoped++;

        return _metadatasPayload;
      };

      container.registerSingleton<OfflineContextParams>(
        OfflineContextParams()..register(_AcmeWorkspace()),
      );
      addTearDown(() => container.unregister<OfflineContextParams>());

      provider.setPrefix('/{workspace}');

      expect((await provider.getMetadatas())?['workspace_user'], isNotNull);
      expect(scoped, 1);
      expect(provider.scope, '/acme');
    });

    test('fetches again after a failed attempt', () async {
      adapter.offline = true;
      expect(await provider.getMetadatas(), isNull);

      var calls = 0;
      adapter.offline = false;
      adapter.routes['GET /dataset/metadatas'] = (options) {
        calls++;

        return _metadatasPayload;
      };

      expect((await provider.getMetadatas())?['workspace_user'], isNotNull);
      expect(calls, 1);
    });
  });
}
