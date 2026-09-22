/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert' show utf8;

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
    final response = err.response;
    final statusCode = response?.statusCode ?? '???';
    final method = err.requestOptions.method;
    final uri = err.requestOptions.uri;

    _logger.fine('✖ $statusCode $method $uri');

    if (response == null) {
      // No status code: the transport itself failed (timeout, offline, abort),
      // and dio's message is the only thing that says which. A status tells the
      // story on its own, where that message only restates what a 404 means.
      _logger.fine('Error: ${err.message}');
    } else if (logBody) {
      final body = _readableBody(response.data);

      if (body != null) {
        _logger.fine('Error body: $body');
      }
    }

    handler.next(err);
  }

  /// The error payload as text, or null when there is nothing readable to
  /// print: a request that asked for bytes (an image, a download) answers its
  /// error as bytes too, which print as a list of character codes.
  String? _readableBody(Object? data) {
    if (data is List<int>) {
      try {
        final decoded = utf8.decode(data);

        return decoded.isEmpty ? null : decoded;
      } on FormatException {
        return null;
      }
    }

    final text = data?.toString();

    return text == null || text.isEmpty ? null : text;
  }
}
