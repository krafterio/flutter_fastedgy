/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:dio/dio.dart';

import '../../auth/auth_provider.dart';
import '../../logging/logger.dart';
import '../http_error.dart';

/// Queue item for pending requests waiting for token refresh
class _QueueItem {
  final Completer<bool> completer;
  final CancelToken? cancelToken;

  _QueueItem({required this.completer, this.cancelToken});
}

/// Shared lock for coordinating token refresh across interceptors
///
/// This class implements the single-flight pattern to ensure only one
/// refresh token request is made at a time, even when multiple requests
/// fail with 401 simultaneously.
///
/// Similar to the Vue.js vue-fastedgy implementation in plugins/fetcher.js
class RefreshTokenLock {
  final AuthProvider _authProvider;
  final _logger = getLogger('RefreshTokenLock');

  bool _isRefreshing = false;
  final List<_QueueItem> _failedQueue = [];
  bool _isRedirecting = false;

  RefreshTokenLock(this._authProvider);

  /// Whether a refresh is currently in progress
  bool get isRefreshing => _isRefreshing;

  /// Handle logout if not already redirecting
  Future<void> _handleLogout() async {
    if (!_isRedirecting) {
      _isRedirecting = true;
      await _authProvider.logout();
      _isRedirecting = false;
    }
  }

  /// Whether a redirect/logout is in progress
  bool get isRedirecting => _isRedirecting;

  bool _isAborted(_QueueItem item) =>
      item.cancelToken != null && item.cancelToken!.isCancelled;

  /// Process the queue after refresh completes
  /// Resolves or rejects all pending requests
  ///
  /// Aborted requests are settled too (with false): dropping them without
  /// completing would leave their caller awaiting a future nobody will ever
  /// complete, and the interceptor chain pending for the life of the app.
  void _processQueue([Object? error]) {
    for (final item in _failedQueue) {
      item.completer.complete(error == null && !_isAborted(item));
    }

    _failedQueue.clear();
  }

  /// Clean up aborted requests from the queue
  void _cleanupAbortedRequests() {
    if (_failedQueue.isNotEmpty) {
      final aborted = _failedQueue.where(_isAborted).toList();
      _failedQueue.removeWhere(_isAborted);

      for (final item in aborted) {
        item.completer.complete(false);
      }
    }
  }

  /// Execute token refresh with single-flight lock
  ///
  /// If a refresh is already in progress, waits for it to complete.
  /// Otherwise, initiates a new refresh.
  ///
  /// Returns true if refresh was successful, false otherwise.
  Future<bool> refreshToken({CancelToken? cancelToken}) async {
    if (_isRefreshing) {
      _logger.finer('Refresh already in progress, waiting...');

      final queueItem = _QueueItem(
        completer: Completer<bool>(),
        cancelToken: cancelToken,
      );
      _failedQueue.add(queueItem);

      return queueItem.completer.future;
    }

    _isRefreshing = true;
    _logger.fine('Starting token refresh');

    try {
      final refreshSuccess = await _authProvider.refreshToken();

      if (refreshSuccess) {
        _logger.finer('Token refresh successful');
        _processQueue();
        return true;
      } else {
        // false means definitive failure (no refresh token, empty response)
        _logger.fine('Token refresh failed');
        _processQueue(Exception('Token refresh failed'));
        await _handleLogout();
        return false;
      }
    } on NetworkError catch (e) {
      // Network error: do NOT logout, the server may come back
      _logger.fine('Network error during token refresh: $e');
      _processQueue(e);
      return false;
    } on HttpError catch (e) {
      if (e is UnauthorizedError || e.statusCode == 403) {
        // Auth rejection: logout
        _logger.fine('Auth rejected during token refresh: $e');
        _processQueue(e);
        await _handleLogout();
        return false;
      }
      // Server error (5xx) or other HTTP error: do NOT logout
      _logger.fine('Server error during token refresh (${e.statusCode}): $e');
      _processQueue(e);
      return false;
    } catch (e) {
      // Unknown exception: do NOT logout
      _logger.fine('Unexpected error during token refresh: $e');
      _processQueue(e);
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Add a request to the queue and wait for refresh to complete
  ///
  /// Used by RefreshTokenInterceptor when a 401 is received while
  /// a refresh is already in progress.
  Future<bool> waitForRefresh(CancelToken? cancelToken) async {
    _cleanupAbortedRequests();

    final queueItem = _QueueItem(
      completer: Completer<bool>(),
      cancelToken: cancelToken,
    );

    _failedQueue.add(queueItem);

    return queueItem.completer.future;
  }

  /// Trigger refresh if not already in progress and add to queue
  ///
  /// Used by RefreshTokenInterceptor to initiate refresh when
  /// a 401 is received.
  Future<bool> triggerRefresh({CancelToken? cancelToken}) async {
    _cleanupAbortedRequests();
    return refreshToken(cancelToken: cancelToken);
  }
}
