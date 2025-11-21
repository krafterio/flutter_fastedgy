/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Result of an authentication operation
class AuthResult {
  /// Whether the operation was successful
  final bool success;

  /// Error message if the operation failed
  final String? message;

  /// User data if login/register was successful
  final Map<String, dynamic>? user;

  /// Access token if login/register was successful
  final String? accessToken;

  /// Refresh token if login/register was successful
  final String? refreshToken;

  const AuthResult({
    required this.success,
    this.message,
    this.user,
    this.accessToken,
    this.refreshToken,
  });

  /// Create a successful result
  factory AuthResult.success({
    Map<String, dynamic>? user,
    String? accessToken,
    String? refreshToken,
  }) {
    return AuthResult(
      success: true,
      user: user,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  /// Create a failure result
  factory AuthResult.failure(String message) {
    return AuthResult(
      success: false,
      message: message,
    );
  }
}
