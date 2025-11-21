/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../../logging/logger.dart';

/// Interceptor that logs all HTTP requests and responses
///
/// Logs:
/// - Request: method, URL, headers, body
/// - Response: status code, headers, body
/// - Errors: error type, message, stack trace
class LoggingInterceptor extends Interceptor {
  final _log = getLogger('HTTP');
  final bool logHeaders;
  final bool logBody;

  LoggingInterceptor({
    this.logHeaders = false,
    this.logBody = true,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log.info('→ ${options.method} ${options.uri}');

    if (logHeaders && options.headers.isNotEmpty) {
      _log.fine('Headers: ${options.headers}');
    }

    if (logBody && options.data != null) {
      _log.fine('Body: ${options.data}');
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final statusCode = response.statusCode;
    final method = response.requestOptions.method;
    final uri = response.requestOptions.uri;

    _log.info('← $statusCode $method $uri');

    if (logHeaders && response.headers.map.isNotEmpty) {
      _log.fine('Headers: ${response.headers.map}');
    }

    if (logBody && response.data != null) {
      _log.fine('Body: ${response.data}');
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode ?? '???';
    final method = err.requestOptions.method;
    final uri = err.requestOptions.uri;

    _log.warning('✖ $statusCode $method $uri');

    if (err.response != null && logBody && err.response!.data != null) {
      _log.fine('Error body: ${err.response!.data}');
    }

    _log.fine('Error: ${err.message}');

    handler.next(err);
  }
}
