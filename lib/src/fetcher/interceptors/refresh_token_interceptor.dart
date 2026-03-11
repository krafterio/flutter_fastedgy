/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../../auth/token_storage.dart';
import '../../logging/logger.dart';
import 'refresh_token_lock.dart';

/// Interceptor that automatically refreshes the access token on 401 errors
///
/// When a request fails with 401 (Unauthorized), this interceptor:
/// 1. Uses RefreshTokenLock to coordinate with other requests
/// 2. Waits if a refresh is already in progress (single-flight pattern)
/// 3. Retries the original request with the new token
/// 4. If refresh fails, lets the error propagate
///
/// Similar to the Vue.js vue-fastedgy fetch:error handler in plugins/fetcher.js
class RefreshTokenInterceptor extends Interceptor {
  final RefreshTokenLock _lock;
  final Dio _dio;
  final TokenStorage _tokenStorage;
  final _logger = getLogger('RefreshTokenInterceptor');

  RefreshTokenInterceptor(this._lock, this._dio, this._tokenStorage);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only handle 401 errors, exclude auth/refresh to avoid infinite loop
    // (like Vue.js: error?.response?.status !== 401 || url.includes('auth/refresh'))
    if (err.response?.statusCode != 401 ||
        err.requestOptions.path.contains('auth/refresh')) {
      return handler.next(err);
    }

    // Check if user can refresh (has refresh token) - like Vue.js canRefreshToken
    if (!await _tokenStorage.canRefreshToken()) {
      _logger.finer('No refresh token available, skipping refresh');
      return handler.next(err);
    }

    _logger.fine('401 Unauthorized detected, attempting token refresh');

    try {
      // Use the shared lock to refresh token (handles queuing)
      final refreshed = await _lock.triggerRefresh(
        cancelToken: err.requestOptions.cancelToken,
      );

      if (!refreshed) {
        _logger.fine('Token refresh failed');
        return handler.next(err);
      }

      // Check if request was cancelled while waiting
      if (err.requestOptions.cancelToken?.isCancelled ?? false) {
        _logger.finer('Request was cancelled while waiting for refresh');
        return handler.next(err);
      }

      _logger.finer('Token refreshed successfully, retrying request');

      // Get the new access token
      final newToken = await _tokenStorage.getAccessToken();

      if (newToken == null) {
        _logger.fine('No access token after refresh');
        return handler.next(err);
      }

      // Clone the failed request with the new token
      final requestOptions = err.requestOptions;
      requestOptions.headers['Authorization'] = 'Bearer $newToken';

      // Retry the request
      final response = await _dio.fetch(requestOptions);

      // Return the successful response
      return handler.resolve(response);
    } catch (e) {
      _logger.fine('Error during token refresh: $e');
      return handler.next(err);
    }
  }
}
