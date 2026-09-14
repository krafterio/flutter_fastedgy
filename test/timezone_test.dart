/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize dotenv for tests (required by Fetcher.create)
  setUpAll(() async {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  group('TimezoneProvider', () {
    test('knows no timezone before initialization', () {
      expect(TimezoneProvider().getTimezone(), isNull);
    });

    test('initializes from the device timezone', () async {
      final provider = _SequenceTimezoneProvider(['Europe/Paris']);
      await provider.initialize();

      expect(provider.getTimezone(), equals('Europe/Paris'));
    });

    test('keeps the last known timezone when it cannot be read', () async {
      final provider = _SequenceTimezoneProvider(['Europe/Paris', null]);
      await provider.initialize();
      await provider.refresh();

      expect(provider.getTimezone(), equals('Europe/Paris'));
    });

    test('reads the timezone again when the application resumes', () async {
      final provider = _SequenceTimezoneProvider([
        'Europe/Paris',
        'America/Guadeloupe',
      ]);
      await provider.initialize();

      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(provider.getTimezone(), equals('America/Guadeloupe'));
    });

    test('clearCache forgets the timezone', () async {
      final provider = _SequenceTimezoneProvider(['Europe/Paris']);
      await provider.initialize();

      provider.clearCache();

      expect(provider.getTimezone(), isNull);
    });
  });

  group('TimezoneInterceptor', () {
    test('adds X-Timezone header to request', () async {
      final provider = _SequenceTimezoneProvider(['America/Guadeloupe']);
      await provider.initialize();
      final handler = _MockRequestInterceptorHandler();

      await TimezoneInterceptor(provider)
          .onRequest(RequestOptions(path: '/test'), handler);

      expect(
        handler.options!.headers['X-Timezone'],
        equals('America/Guadeloupe'),
      );
    });

    test('sends no header while the timezone is unknown', () async {
      final handler = _MockRequestInterceptorHandler();

      await TimezoneInterceptor(TimezoneProvider())
          .onRequest(RequestOptions(path: '/test'), handler);

      expect(handler.options!.headers.containsKey('X-Timezone'), isFalse);
    });

    test('preserves existing headers', () async {
      final provider = _SequenceTimezoneProvider(['Europe/Paris']);
      await provider.initialize();
      final options = RequestOptions(
        path: '/test',
        headers: {
          'Authorization': 'Bearer token123',
          'Custom-Header': 'custom-value',
        },
      );
      final handler = _MockRequestInterceptorHandler();

      await TimezoneInterceptor(provider).onRequest(options, handler);

      expect(
        handler.options!.headers['Authorization'],
        equals('Bearer token123'),
      );
      expect(handler.options!.headers['Custom-Header'], equals('custom-value'));
      expect(handler.options!.headers['X-Timezone'], equals('Europe/Paris'));
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
      dio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost:8000',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
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
      final testDio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost:8000',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

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
      final testDio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost:8000',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

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

/// Provider reading its timezones from a list, the last one repeating.
class _SequenceTimezoneProvider extends TimezoneProvider {
  _SequenceTimezoneProvider(this._timezones);

  final List<String?> _timezones;
  int _reads = 0;

  @override
  Future<String?> detect() async {
    final index = _reads < _timezones.length ? _reads : _timezones.length - 1;
    _reads++;

    return _timezones[index];
  }
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
