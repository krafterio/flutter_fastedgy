/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../fetcher/http_error.dart';

/// Whether [error] denotes a connectivity failure (no network, unreachable
/// server, timeout) rather than an applicative server error.
///
/// The offline layer only falls back to the local cache on connectivity
/// failures: real server responses (4xx/5xx) are always rethrown.
bool isOfflineError(Object error) {
  if (error is NetworkError) {
    return true;
  }

  if (error is HttpError) {
    return error.statusCode == null;
  }

  if (error is DioException) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  return false;
}

/// The HTTP status code carried by [error], if any.
int? errorStatusCode(Object error) {
  if (error is HttpError) {
    return error.statusCode;
  }

  if (error is DioException) {
    return error.response?.statusCode;
  }

  return null;
}

/// Whether [error] is a transient server failure (5xx, 429) that must be
/// retried later rather than treated as a definitive rejection.
bool isRetryableServerError(Object error) {
  final status = errorStatusCode(error);

  return status != null && (status >= 500 || status == 429);
}
