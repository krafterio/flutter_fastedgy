/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

/// Interceptor for global error handling
///
/// This interceptor can be used to:
/// - Log errors globally
/// - Transform errors before they reach the caller
/// - Add custom error handling logic
///
/// Note: HttpError transformation is done in the Fetcher catch blocks,
/// not here, to maintain clean error propagation.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // For now, just pass through
    // Custom error handling can be added here in the future
    handler.next(err);
  }
}
