/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../../logging/logger.dart';

/// Retries a request when the underlying HTTP socket was killed by the
/// OS/proxy while the app was idle (typical scenario: app comes back from
/// background, cached Keep-Alive sockets are dead, the first requests on
/// them fail before the server receives them).
///
/// Retries [DioExceptionType.connectionError] for any method, and the
/// timeout types only for idempotent methods (GET/HEAD/OPTIONS) — a timeout
/// may have already reached the server, so retrying a mutation could
/// double-execute it.
///
/// Bounded to [_maxRetries] attempts per request via a counter on
/// [RequestOptions.extra]. A budget (rather than a one-shot boolean) keeps
/// the interceptor self-contained: when a 401 triggers a token refresh and
/// the request is replayed with the new token, that fresh attempt can still
/// consume a remaining retry if it lands on another dead socket — without
/// RefreshTokenInterceptor having to reach into this interceptor's state.
class ConnectionRetryInterceptor extends Interceptor {
  final Dio _dio;
  final _logger = getLogger('ConnectionRetry');

  static const String _retryCountKey = '_connection_retry_count';
  static const int _maxRetries = 2;

  static const _idempotentMethods = {'GET', 'HEAD', 'OPTIONS'};

  ConnectionRetryInterceptor(this._dio);

  bool _isRetryable(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _idempotentMethods.contains(
          err.requestOptions.method.toUpperCase(),
        );
      default:
        return false;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_isRetryable(err)) {
      return handler.next(err);
    }

    final requestOptions = err.requestOptions;

    if (requestOptions.cancelToken?.isCancelled ?? false) {
      return handler.next(err);
    }

    final attempts = (requestOptions.extra[_retryCountKey] as int?) ?? 0;

    if (attempts >= _maxRetries) {
      _logger.fine(
        'Transient error after $attempts retries, giving up: ${requestOptions.method} ${requestOptions.path}',
      );
      return handler.next(err);
    }

    requestOptions.extra[_retryCountKey] = attempts + 1;
    _logger.fine(
      'Stale socket detected, retry ${attempts + 1}/$_maxRetries: ${requestOptions.method} ${requestOptions.path}',
    );

    try {
      final response = await _dio.fetch(requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
