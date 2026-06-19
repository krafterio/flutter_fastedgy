/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'auth_result.dart';

/// Abstract authentication provider
///
/// This interface defines the contract for authentication providers.
/// Apps can extend this to implement custom authentication logic.
///
/// Example:
/// ```dart
/// class AppAuthProvider implements AuthProvider {
///   @override
///   Future<AuthResult> login(String username, String password) async {
///     // Custom authentication logic
///   }
///
///   // Custom methods
///   Future<void> loginWithBiometric() async {
///     // Biometric authentication
///   }
/// }
///
/// // Register in main.dart
/// await initializeFastEdgy(
///   authProvider: AppAuthProvider(),
/// );
/// ```
abstract class AuthProvider<TUser> {
  /// Login with username and password
  Future<AuthResult<TUser>> login(String username, String password);

  /// Register a new user
  Future<AuthResult<TUser>> register(Map<String, dynamic> userData);

  /// Logout the current user
  Future<void> logout();

  /// Get the current access token
  Future<String?> getAccessToken();

  /// Get a non-expired access token, refreshing it when the stored one has
  /// expired.
  ///
  /// Use this anywhere the token is read directly — notably WebSocket
  /// handshakes, which bypass the HTTP refresh interceptor that guards REST
  /// calls. Without it, once the access token crosses its TTL the handshake
  /// hands the server a stale token: the server rejects it and closes the
  /// socket before it is ready.
  Future<String?> getValidatedAccessToken();

  /// Get the current refresh token
  Future<String?> getRefreshToken();

  /// Refresh the access token using the refresh token
  Future<bool> refreshToken();

  /// Check if the user is authenticated
  Future<bool> isAuthenticated();

  /// Get the current user data
  Future<TUser?> getCurrentUser();
}
