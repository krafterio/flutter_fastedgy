/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../../auth/token_storage.dart';
import '../../logging/logger.dart';
import 'refresh_token_lock.dart';

/// Marks a request already replayed once after a refresh.
///
/// The replay goes back through the whole interceptor chain, so without this
/// an endpoint answering 401 for a reason no token can fix keeps the cycle
/// going for as long as the refresh succeeds: refresh, retry, 401, refresh.
const _retriedKey = 'fastedgy.refreshRetried';

/// Path segment of the endpoints where a 401 is the answer, not an expired
/// token: signing in with the wrong password, or presenting a refresh token
/// the server no longer accepts. Refreshing turns neither into a success.
///
/// The surrounding slashes keep out a resource whose name merely starts the
/// same way, `/authors` never matching `/auth/`.
const _neverRefreshedPath = '/auth/';

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
    if (err.response?.statusCode != 401 ||
        err.requestOptions.path.contains(_neverRefreshedPath)) {
      return handler.next(err);
    }

    if (err.requestOptions.extra[_retriedKey] == true) {
      _logger.fine('Already replayed after a refresh, letting the 401 through');

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
      requestOptions.extra[_retriedKey] = true;

      // Retry the request
      final response = await _dio.fetch(requestOptions);

      // Return the successful response
      return handler.resolve(response);
    } catch (e, stackTrace) {
      // The lock answers every refresh outcome with a bool, logging out on a
      // rejected refresh token and holding the session on a network or 5xx
      // failure, so what lands here is the replay. Its error is dropped in
      // favour of the original 401 handed back to the caller: without this
      // line it would be lost. The pipeline reads the argument to demote an
      // unanswered server to a single INFO line.
      _logger.warning('Replay after a refresh failed', e, stackTrace);

      return handler.next(err);
    }
  }
}
