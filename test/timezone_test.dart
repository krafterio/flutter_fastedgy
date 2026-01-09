/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize dotenv for tests (required by Fetcher.create)
  setUpAll(() async {
    // Create a test .env file content in memory
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  group('TimezoneProvider', () {
    test('returns UTC before initialization', () {
      final provider = TimezoneProvider();
      expect(provider.getTimezone(), equals('UTC'));
    });

    test('initializes and caches timezone', () async {
      final provider = TimezoneProvider();
      await provider.initialize();

      final timezone = provider.getTimezone();
      expect(timezone, isNotEmpty);
      expect(timezone, isA<String>());

      // Should return same value on subsequent calls (cached)
      final timezone2 = provider.getTimezone();
      expect(timezone2, equals(timezone));
    });

    test('clearCache resets timezone to UTC', () async {
      final provider = TimezoneProvider();
      await provider.initialize();

      final timezone = provider.getTimezone();
      expect(timezone, isNotEmpty);

      provider.clearCache();
      expect(provider.getTimezone(), equals('UTC'));
    });

    test('can re-initialize after clearing cache', () async {
      final provider = TimezoneProvider();
      await provider.initialize();

      final timezone1 = provider.getTimezone();
      expect(timezone1, isNotEmpty);

      provider.clearCache();
      expect(provider.getTimezone(), equals('UTC'));

      await provider.initialize();
      final timezone2 = provider.getTimezone();
      expect(timezone2, equals(timezone1));
    });

    test('initialize is idempotent', () async {
      final provider = TimezoneProvider();

      await provider.initialize();
      final timezone1 = provider.getTimezone();

      // Second initialization should not change the value
      await provider.initialize();
      final timezone2 = provider.getTimezone();

      expect(timezone2, equals(timezone1));
    });
  });

  group('TimezoneInterceptor', () {
    late TimezoneProvider provider;
    late TimezoneInterceptor interceptor;

    setUp(() async {
      provider = TimezoneProvider();
      await provider.initialize();
      interceptor = TimezoneInterceptor(provider);
    });

    test('adds X-Timezone header to request', () async {
      final options = RequestOptions(path: '/test');
      final handler = _MockRequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(handler.options!.headers['X-Timezone'], isNotEmpty);
      expect(handler.options!.headers['X-Timezone'], equals(provider.getTimezone()));
    });

    test('uses UTC when provider not initialized', () async {
      final uninitializedProvider = TimezoneProvider();
      final uninitializedInterceptor = TimezoneInterceptor(uninitializedProvider);

      final options = RequestOptions(path: '/test');
      final handler = _MockRequestInterceptorHandler();

      await uninitializedInterceptor.onRequest(options, handler);

      expect(handler.options!.headers['X-Timezone'], equals('UTC'));
    });

    test('preserves existing headers', () async {
      final options = RequestOptions(
        path: '/test',
        headers: {
          'Authorization': 'Bearer token123',
          'Custom-Header': 'custom-value',
        },
      );
      final handler = _MockRequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(handler.options!.headers['Authorization'], equals('Bearer token123'));
      expect(handler.options!.headers['Custom-Header'], equals('custom-value'));
      expect(handler.options!.headers['X-Timezone'], isNotEmpty);
    });
  });

  group('Fetcher with Timezone', () {
    late TimezoneProvider provider;
    late Dio dio;
    late Bus bus;

    setUp(() async {
      initializeContainer();

      // Create and register Bus (required by Fetcher)
      bus = Bus();
      container.registerSingleton<Bus>(bus);

      // Create and register TimezoneProvider
      provider = TimezoneProvider();
      await provider.initialize();
      container.registerSingleton<TimezoneProvider>(provider);

      // Create Dio instance directly to avoid dotenv dependency in tests
      dio = Dio(BaseOptions(
        baseUrl: 'http://localhost:8000',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ));
    });

    tearDown(() {
      container.reset();
    });

    test('Fetcher.create includes timezone interceptor by default', () {
      final fetcher = Fetcher.create(dio: dio, bus: bus);

      expect(fetcher, isNotNull);
      // Verify timezone interceptor is in the list
      expect(
        dio.interceptors.any((i) => i is TimezoneInterceptor),
        isTrue,
        reason: 'TimezoneInterceptor should be added by default',
      );
    });

    test('Fetcher.create respects enableTimezone flag', () {
      // Create new Dio for this test
      final testDio = Dio(BaseOptions(
        baseUrl: 'http://localhost:8000',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ));

      final fetcher = Fetcher.create(
        enableTimezone: false,
        dio: testDio,
        bus: bus,
      );

      expect(fetcher, isNotNull);
      // Verify timezone interceptor is NOT in the list
      expect(
        testDio.interceptors.any((i) => i is TimezoneInterceptor),
        isFalse,
        reason: 'TimezoneInterceptor should not be added when disabled',
      );
    });

    test('custom interceptor with timezone works', () {
      // Create new Dio for this test
      final testDio = Dio(BaseOptions(
        baseUrl: 'http://localhost:8000',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ));

      final customInterceptor = TimezoneInterceptor(provider);

      final fetcher = Fetcher.create(
        enableTimezone: false,
        customInterceptors: [
          InterceptorConfig(customInterceptor, priority: 100),
        ],
        dio: testDio,
        bus: bus,
      );

      expect(fetcher, isNotNull);
      // Verify timezone interceptor is in the list (from custom interceptors)
      expect(
        testDio.interceptors.any((i) => i is TimezoneInterceptor),
        isTrue,
        reason: 'Custom TimezoneInterceptor should be added',
      );
    });
  });
}

/// Mock handler for testing interceptors
class _MockRequestInterceptorHandler extends RequestInterceptorHandler {
  RequestOptions? options;

  @override
  void next(RequestOptions options) {
    this.options = options;
  }

  @override
  void reject(DioException error, [bool newError = false]) {
    // Not used in these tests
  }

  @override
  void resolve(Response response, [bool newResponse = false]) {
    // Not used in these tests
  }
}
