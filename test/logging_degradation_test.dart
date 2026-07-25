/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpError httpError(int status) => HttpError.fromDioException(
    DioException(
      requestOptions: RequestOptions(path: '/members'),
      response: Response(
        requestOptions: RequestOptions(path: '/members'),
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    ),
  );

  DioException connectionError() => DioException(
    requestOptions: RequestOptions(path: '/members'),
    type: DioExceptionType.connectionError,
    error: 'Connection refused',
  );

  group('isServerUnavailable', () {
    test('covers connectivity failures and unservable statuses', () {
      expect(isServerUnavailable(connectionError()), isTrue);
      expect(isServerUnavailable(httpError(502)), isTrue);
      expect(isServerUnavailable(httpError(503)), isTrue);
      expect(isServerUnavailable(httpError(504)), isTrue);
      expect(isServerUnavailable(httpError(500)), isFalse);
      expect(isServerUnavailable(httpError(404)), isFalse);
    });

    test('stays wider than the connectivity-only isOfflineError', () {
      expect(isOfflineError(connectionError()), isTrue);
      expect(isOfflineError(httpError(503)), isFalse);
    });
  });

  group('HttpError.fromDioException', () {
    test('states the cause without the dio library disclaimer', () {
      final error = HttpError.fromDioException(
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/members'),
          reason: 'Connection refused',
        ),
      );

      expect(error, isA<NetworkError>());
      expect(error.message, isNot(contains('This indicates an error')));
      expect(error.message, isNot(contains('Connection refused')));
    });
  });
}
