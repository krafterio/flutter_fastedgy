/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Dio buildDio(_ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(ConnectionRetryInterceptor(dio));
    return dio;
  }

  group('ConnectionRetryInterceptor', () {
    test('retries once on connection error then succeeds', () async {
      final adapter = _ScriptedAdapter(failTimes: 1);
      final dio = buildDio(adapter);

      final res = await dio.get<dynamic>('/x');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('recovers when the post-refresh replay also hits a stale socket '
        '(budget of 2 retries)', () async {
      final adapter = _ScriptedAdapter(failTimes: 2);
      final dio = buildDio(adapter);

      final res = await dio.get<dynamic>('/x');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 3);
    });

    test('gives up after exhausting the retry budget', () async {
      final adapter = _ScriptedAdapter(failTimes: 99);
      final dio = buildDio(adapter);

      await expectLater(
        dio.get<dynamic>('/x'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionError,
          ),
        ),
      );
      expect(adapter.callCount, 3);
    });

    test('retries idempotent timeouts', () async {
      final adapter = _ScriptedAdapter(
        failTimes: 1,
        failType: DioExceptionType.receiveTimeout,
      );
      final dio = buildDio(adapter);

      final res = await dio.get<dynamic>('/x');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('does not retry timeouts on non-idempotent methods', () async {
      final adapter = _ScriptedAdapter(
        failTimes: 1,
        failType: DioExceptionType.receiveTimeout,
      );
      final dio = buildDio(adapter);

      await expectLater(
        dio.post<dynamic>('/x', data: {'a': 1}),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
    });
  });
}

class _ScriptedAdapter implements HttpClientAdapter {
  int callCount = 0;
  final int failTimes;
  final DioExceptionType failType;

  _ScriptedAdapter({
    required this.failTimes,
    this.failType = DioExceptionType.connectionError,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    if (callCount <= failTimes) {
      throw DioException(requestOptions: options, type: failType);
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
