/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
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
  final Fetcher? _fetcher;
  final TokenStorage _tokenStorage;
  final Bus _bus;
  final _logger = getLogger('AuthProvider');

  Map<String, dynamic>? _currentUser;

  DefaultAuthProvider(this._fetcher, this._tokenStorage, this._bus);

  /// Get the Fetcher instance
  ///
  /// Uses the stored _fetcher if provided, otherwise retrieves from container.
  /// This allows breaking the circular dependency during initialization.
  Fetcher get _getFetcher => _fetcher ?? getService<Fetcher>();

  @override
  Future<AuthResult> login(String username, String password) async {
    try {
      _logger.finer('Attempting login');

      final response = await _getFetcher.post(
        '/auth/token',
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
      _bus.fire(const AuthLoggedEvent());

      _logger.finer('Login successful');

      return AuthResult.success(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: _currentUser,
      );
    } on HttpError catch (e) {
      _logger.severe('Login failed: ${e.message}');
      return AuthResult.failure(e.message);
    } catch (e, stackTrace) {
      _logger.severe('Unexpected error during login', e, stackTrace);
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  @override
  Future<AuthResult> register(Map<String, dynamic> userData) async {
    try {
      _logger.finer('Attempting registration');

      final response = await _getFetcher.post('/auth/register', userData);

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
      _bus.fire(const AuthLoggedEvent());

      _logger.finer('Registration successful');

      return AuthResult.success(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: _currentUser,
      );
    } on HttpError catch (e) {
      _logger.severe('Registration failed: ${e.message}');
      return AuthResult.failure(e.message);
    } catch (e, stackTrace) {
      _logger.severe('Unexpected error during registration', e, stackTrace);
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  @override
  Future<void> logout() async {
    _logger.finer('Logging out');

    await _tokenStorage.clearTokens();
    _currentUser = null;

    // Fire auth:logout event
    _bus.fire(const AuthLogoutEvent());

    _logger.finer('Logout complete');
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
        _logger.warning('No refresh token available');
        return false;
      }

      _logger.finer('Refreshing token');

      final response = await _getFetcher.post(
        '/auth/refresh',
        {
          'refresh_token': refreshToken,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String?;

      if (newAccessToken != null) {
        await _tokenStorage.saveAccessToken(newAccessToken);
        _logger.finer('Token refreshed successfully');
        return true;
      }

      _logger.warning('No access token in refresh response');
      return false;
    } on HttpError catch (e) {
      _logger.severe('Token refresh failed: ${e.message}');
      // If refresh fails, logout
      await logout();
      return false;
    } catch (e, stackTrace) {
      _logger.severe('Unexpected error during token refresh', e, stackTrace);
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
        final response = await _getFetcher.get('/me');
        _currentUser = response.data as Map<String, dynamic>?;
        return _currentUser;
      } catch (e) {
        _logger.warning('Failed to fetch current user: $e');
      }
    }

    return null;
  }
}
