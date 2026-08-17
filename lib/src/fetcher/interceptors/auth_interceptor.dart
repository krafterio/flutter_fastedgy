/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../../auth/token_storage.dart';
import '../../logging/logger.dart';
import 'refresh_token_lock.dart';

/// Interceptor that automatically adds the Authorization header to requests
///
/// Injects the Bearer token from TokenStorage into every request.
/// Also proactively refreshes token if expired before making request.
///
/// Similar to the Vue.js vue-fastedgy fetch:request handler in plugins/fetcher.js
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  final RefreshTokenLock? _lock;
  final _logger = getLogger('AuthInterceptor');

  AuthInterceptor(this._tokenStorage, [this._lock]);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Check if user is authenticated first (like Vue.js isAuthenticated)
    // If not authenticated, skip everything
    if (!await _tokenStorage.isAuthenticated()) {
      return handler.next(options);
    }

    // Exclude auth/refresh to avoid infinite loop (like Vue.js !url.includes('auth/refresh'))
    if (options.path.contains('auth/refresh')) {
      return handler.next(options);
    }

    // Proactive token refresh if expired (like Vue.js isTokenExpired && canRefreshToken)
    final lock = _lock;
    if (lock != null &&
        await _tokenStorage.isTokenExpired() &&
        await _tokenStorage.canRefreshToken()) {
      _logger.finer('Token expired, refreshing proactively...');

      final refreshed = await lock.refreshToken(
        cancelToken: options.cancelToken,
      );

      if (!refreshed) {
        _logger.fine('Proactive token refresh failed');
        // Continue anyway, the 401 will be handled by RefreshTokenInterceptor
      }
    }

    // Get the access token
    final token = await _tokenStorage.getAccessToken();

    // Add Authorization header if token exists
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }
}
