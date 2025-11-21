/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../fetcher/client.dart';
import '../fetcher/http_error.dart';
import '../logging/logger.dart';
import '../bus/bus.dart';
import 'auth_provider.dart';
import 'auth_result.dart';
import 'token_storage.dart';
import 'auth_events.dart';

/// Default implementation of AuthProvider
///
/// Provides standard FastEdgy authentication with JWT tokens.
class DefaultAuthProvider implements AuthProvider {
  final Fetcher _fetcher;
  final TokenStorage _tokenStorage;
  final Bus _bus;
  final _log = getLogger('DefaultAuthProvider');

  Map<String, dynamic>? _currentUser;

  DefaultAuthProvider(this._fetcher, this._tokenStorage, this._bus);

  @override
  Future<AuthResult> login(String username, String password) async {
    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$apiBaseUrl/auth/token';

      _log.info('Attempting login to $url');

      final response = await _fetcher.post(
        url,
        {
          'username': username,
          'password': password,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessToken != null) {
        await _tokenStorage.saveAccessToken(accessToken);
      }
      if (refreshToken != null) {
        await _tokenStorage.saveRefreshToken(refreshToken);
      }

      // Store user data if present
      _currentUser = data['user'] as Map<String, dynamic>?;

      // Fire auth:logged event
      _bus.fire(AuthLoggedEvent());

      _log.info('Login successful');

      return AuthResult.success(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: _currentUser,
      );
    } on HttpError catch (e) {
      _log.severe('Login failed: ${e.message}');
      return AuthResult.failure(e.message);
    } catch (e, stackTrace) {
      _log.severe('Unexpected error during login', e, stackTrace);
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  @override
  Future<AuthResult> register(Map<String, dynamic> userData) async {
    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$apiBaseUrl/auth/register';

      _log.info('Attempting registration to $url');

      final response = await _fetcher.post(url, userData);

      final data = response.data as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessToken != null) {
        await _tokenStorage.saveAccessToken(accessToken);
      }
      if (refreshToken != null) {
        await _tokenStorage.saveRefreshToken(refreshToken);
      }

      // Store user data if present
      _currentUser = data['user'] as Map<String, dynamic>?;

      // Fire auth:logged event
      _bus.fire(AuthLoggedEvent());

      _log.info('Registration successful');

      return AuthResult.success(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: _currentUser,
      );
    } on HttpError catch (e) {
      _log.severe('Registration failed: ${e.message}');
      return AuthResult.failure(e.message);
    } catch (e, stackTrace) {
      _log.severe('Unexpected error during registration', e, stackTrace);
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  @override
  Future<void> logout() async {
    _log.info('Logging out');

    await _tokenStorage.clearTokens();
    _currentUser = null;

    // Fire auth:logout event
    _bus.fire(AuthLogoutEvent());

    _log.info('Logout complete');
  }

  @override
  Future<String?> getAccessToken() async {
    return _tokenStorage.getAccessToken();
  }

  @override
  Future<String?> getRefreshToken() async {
    return _tokenStorage.getRefreshToken();
  }

  @override
  Future<bool> refreshToken() async {
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null) {
        _log.warning('No refresh token available');
        return false;
      }

      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$apiBaseUrl/auth/refresh';

      _log.info('Refreshing token');

      final response = await _fetcher.post(
        url,
        {
          'refresh_token': refreshToken,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String?;

      if (newAccessToken != null) {
        await _tokenStorage.saveAccessToken(newAccessToken);
        _log.info('Token refreshed successfully');
        return true;
      }

      _log.warning('No access token in refresh response');
      return false;
    } on HttpError catch (e) {
      _log.severe('Token refresh failed: ${e.message}');
      // If refresh fails, logout
      await logout();
      return false;
    } catch (e, stackTrace) {
      _log.severe('Unexpected error during token refresh', e, stackTrace);
      await logout();
      return false;
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (_currentUser != null) {
      return _currentUser;
    }

    // Try to fetch user data from API
    if (await isAuthenticated()) {
      try {
        final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
        final url = '$apiBaseUrl/auth/me';

        final response = await _fetcher.get(url);
        _currentUser = response.data as Map<String, dynamic>?;
        return _currentUser;
      } catch (e) {
        _log.warning('Failed to fetch current user: $e');
      }
    }

    return null;
  }
}
