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
  final _logger = getLogger('HTTP');
  final bool logHeaders;
  final bool logBody;

  LoggingInterceptor({this.logHeaders = false, this.logBody = true});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.fine('→ ${options.method} ${options.uri}');

    if (logHeaders && options.headers.isNotEmpty) {
      _logger.finer('Headers: ${options.headers}');
    }

    if (logBody && options.data != null) {
      _logger.finer('Body: ${options.data}');
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final statusCode = response.statusCode;
    final method = response.requestOptions.method;
    final uri = response.requestOptions.uri;

    _logger.fine('← $statusCode $method $uri');

    if (logHeaders && response.headers.map.isNotEmpty) {
      _logger.finer('Headers: ${response.headers.map}');
    }

    if (logBody && response.data != null) {
      _logger.finer('Body: ${response.data}');
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode ?? '???';
    final method = err.requestOptions.method;
    final uri = err.requestOptions.uri;

    _logger.fine('✖ $statusCode $method $uri');

    if (err.response != null && logBody && err.response!.data != null) {
      _logger.fine('Error body: ${err.response!.data}');
    }

    _logger.fine('Error: ${err.message}');

    handler.next(err);
  }
}
