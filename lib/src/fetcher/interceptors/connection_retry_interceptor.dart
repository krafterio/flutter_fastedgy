/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../../logging/logger.dart';

/// Retries a request once when the underlying HTTP socket was killed
/// by the OS/proxy while the app was idle (typical scenario: app comes
/// back from background, the cached Keep-Alive socket is dead, the
/// first request on it fails with a connection error before the server
/// receives it).
///
/// Only retries [DioExceptionType.connectionError] — timeouts and
/// non-2xx responses may have already reached the server and are not
/// safe to retry blindly here.
///
/// Bounded to ONE retry per request via a flag on [RequestOptions.extra]
/// so a genuinely dead network still surfaces as an error after the
/// second attempt.
class ConnectionRetryInterceptor extends Interceptor {
  final Dio _dio;
  final _logger = getLogger('ConnectionRetry');

  static const String _retryFlag = '_connection_retry_done';

  ConnectionRetryInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.type != DioExceptionType.connectionError) {
      return handler.next(err);
    }

    final requestOptions = err.requestOptions;

    if (requestOptions.extra[_retryFlag] == true) {
      _logger.fine(
        'Connection error after retry, giving up: ${requestOptions.method} ${requestOptions.path}',
      );
      return handler.next(err);
    }

    if (requestOptions.cancelToken?.isCancelled ?? false) {
      return handler.next(err);
    }

    _logger.fine(
      'Stale socket detected, retrying: ${requestOptions.method} ${requestOptions.path}',
    );
    requestOptions.extra[_retryFlag] = true;

    try {
      final response = await _dio.fetch(requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
