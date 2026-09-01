/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage for authentication tokens
class TokenStorage {
  static const String _accessTokenKey = 'token';
  static const String _refreshTokenKey = 'refresh_token';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Also reads the tokens a previous version left in the shared preferences,
  /// moving what it finds to the secure storage and clearing it from there
  const TokenStorage({this.legacy = false});

  final bool legacy;

  /// Swaps the keychain for an in-memory one holding [values], keyed as the
  /// tokens are (`token`, `refresh_token`).
  ///
  /// A real keychain answers over a platform channel, which a test pumping its
  /// own clock never gets: every authenticated request would wait on it
  /// forever. Call it from the test setup, before anything reads a token, so an
  /// application never has to reach for the storage package itself.
  @visibleForTesting
  static void setMockInitialValues([Map<String, String> values = const {}]) {
    // This is the seam the annotation asks for, handed to the applications
    // built on top so they never import the storage package themselves.
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues(values);
  }

  /// Save access token
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  /// Save refresh token
  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  /// Get access token
  Future<String?> getAccessToken() => _read(_accessTokenKey);

  /// Get refresh token
  Future<String?> getRefreshToken() => _read(_refreshTokenKey);

  /// Clear all tokens (logout)
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<String?> _read(String key) async {
    final value = await _readSecure(key);

    if (value != null && value.isNotEmpty) {
      return value;
    }

    if (!legacy) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);

    if (legacyValue == null || legacyValue.isEmpty) {
      return null;
    }

    await _storage.write(key: key, value: legacyValue);
    await prefs.remove(key);

    return legacyValue;
  }

  /// A keystore key invalidated by a restore or a lock-screen change makes the
  /// store unreadable: the session is empty rather than an error on startup
  Future<String?> _readSecure(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
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
