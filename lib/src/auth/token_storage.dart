/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage for authentication tokens
class TokenStorage {
  static const String _accessTokenKey = 'token';
  static const String _refreshTokenKey = 'refresh_token';

  /// Save access token
  Future<void> saveAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, token);
  }

  /// Save refresh token
  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  /// Get access token
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  /// Clear all tokens (logout)
  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  /// Check if access token is expired by decoding the JWT payload
  ///
  /// Similar to Vue.js isTokenExpired computed property in stores/auth.js
  Future<bool> isTokenExpired() async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) return true;

    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // Decode the payload (second part of JWT)
      final normalizedPayload = base64Url.normalize(parts[1]);
      final payloadBytes = base64Url.decode(normalizedPayload);
      final payloadString = utf8.decode(payloadBytes);
      final payload = jsonDecode(payloadString) as Map<String, dynamic>;

      final exp = payload['exp'] as int?;
      if (exp == null) return true;

      final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expirationDate);
    } catch (e) {
      // If we can't decode, assume expired to be safe
      return true;
    }
  }

  /// Check if user can refresh token (has refresh token)
  ///
  /// Similar to Vue.js canRefreshToken computed property
  Future<bool> canRefreshToken() async {
    final refreshToken = await getRefreshToken();
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  /// Check if user is authenticated (has both access token and refresh token)
  ///
  /// Similar to Vue.js isAuthenticated computed property
  Future<bool> isAuthenticated() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();
    return accessToken != null &&
        accessToken.isNotEmpty &&
        refreshToken != null &&
        refreshToken.isNotEmpty;
  }
}
