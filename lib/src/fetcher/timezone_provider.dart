/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_timezone/flutter_timezone.dart';

/// Provider for device timezone information
///
/// Fetches and caches the device's local timezone to avoid repeated
/// platform calls. Provides a fallback to 'UTC' if timezone detection fails.
class TimezoneProvider {
  String? _cachedTimezone;

  /// Get the device timezone (cached after first call)
  ///
  /// Returns the timezone identifier (e.g., 'America/New_York', 'Europe/Paris')
  /// Falls back to 'UTC' if detection fails.
  ///
  /// Example:
  /// ```dart
  /// final provider = TimezoneProvider();
  /// await provider.initialize();
  /// final tz = provider.getTimezone(); // 'Europe/Paris'
  /// ```
  String getTimezone() {
    return _cachedTimezone ?? 'UTC';
  }

  /// Initialize timezone detection (call once at app startup)
  ///
  /// This method should be called during app initialization to fetch
  /// and cache the device's timezone. Subsequent calls to [getTimezone]
  /// will return the cached value.
  ///
  /// Example:
  /// ```dart
  /// final provider = TimezoneProvider();
  /// await provider.initialize();
  /// ```
  Future<void> initialize() async {
    if (_cachedTimezone != null) {
      return; // Already initialized
    }

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      _cachedTimezone = timezoneInfo.identifier;
    } catch (e) {
      // Fallback to UTC if timezone detection fails
      _cachedTimezone = 'UTC';
    }
  }

  /// Clear cached timezone (useful for testing)
  void clearCache() {
    _cachedTimezone = null;
  }
}
