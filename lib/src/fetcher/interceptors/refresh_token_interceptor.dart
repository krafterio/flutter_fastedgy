/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../../auth/auth_provider.dart';
import '../../logging/logger.dart';

/// Interceptor that automatically refreshes the access token on 401 errors
///
/// When a request fails with 401 (Unauthorized), this interceptor:
/// 1. Tries to refresh the token via AuthProvider
/// 2. Retries the original request with the new token
/// 3. If refresh fails, lets the error propagate
class RefreshTokenInterceptor extends Interceptor {
  final AuthProvider _authProvider;
  final Dio _dio;
  final _log = getLogger('RefreshTokenInterceptor');

  RefreshTokenInterceptor(this._authProvider, this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only handle 401 errors
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    _log.info('401 Unauthorized detected, attempting token refresh');

    try {
      // Try to refresh the token
      final refreshed = await _authProvider.refreshToken();

      if (!refreshed) {
        _log.warning('Token refresh failed');
        return handler.next(err);
      }

      _log.info('Token refreshed successfully, retrying request');

      // Get the new access token
      final newToken = await _authProvider.getAccessToken();

      if (newToken == null) {
        _log.warning('No access token after refresh');
        return handler.next(err);
      }

      // Clone the failed request with the new token
      final requestOptions = err.requestOptions;
      requestOptions.headers['Authorization'] = 'Bearer $newToken';

      // Retry the request
      final response = await _dio.fetch(requestOptions);

      // Return the successful response
      return handler.resolve(response);
    } catch (e, stackTrace) {
      _log.severe('Error during token refresh', e, stackTrace);
      return handler.next(err);
    }
  }
}
