/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LogRecord record(Object? error) => LogRecord(
    Level.SEVERE,
    'Members load failed',
    'WorkspaceSettingsScreen',
    error,
    StackTrace.current,
  );

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

  group('degradeUnansweredRequest', () {
    test('degrades an unreachable server to a single INFO line', () {
      final degraded = degradeUnansweredRequest(record(connectionError()))!;

      expect(degraded.level, Level.INFO);
      expect(degraded.message, 'Members load failed: server unreachable');
      expect(degraded.error, isNull);
      expect(degraded.stackTrace, isNull);
      expect(degraded.loggerName, 'WorkspaceSettingsScreen');
    });

    test('degrades a server in maintenance, naming its status', () {
      final degraded = degradeUnansweredRequest(record(httpError(503)))!;

      expect(degraded.level, Level.INFO);
      expect(
        degraded.message,
        'Members load failed: server unavailable (HTTP 503)',
      );
    });

    test('keeps a rejection the server did answer', () {
      for (final status in [400, 404, 422, 500]) {
        final original = record(httpError(status));
        final kept = degradeUnansweredRequest(original)!;

        expect(kept, same(original), reason: 'HTTP $status must stay severe');
        expect(kept.level, Level.SEVERE);
        expect(kept.stackTrace, isNotNull);
      }
    });

    test('keeps a record without an error, and one below INFO', () {
      final plain = LogRecord(Level.SEVERE, 'Boom', 'Scope');
      expect(degradeUnansweredRequest(plain), same(plain));

      final fine = LogRecord(
        Level.FINE,
        'Retrying',
        'Scope',
        connectionError(),
      );
      expect(degradeUnansweredRequest(fine), same(fine));
    });

    test('drops the line when INFO is below the configured level', () {
      final previous = Logger.root.level;
      Logger.root.level = Level.WARNING;
      addTearDown(() => Logger.root.level = previous);

      expect(degradeUnansweredRequest(record(connectionError())), isNull);
    });
  });

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
