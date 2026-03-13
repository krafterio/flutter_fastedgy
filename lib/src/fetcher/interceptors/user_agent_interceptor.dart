/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:dio/dio.dart';

/// Interceptor that adds the User-Agent header to all requests
///
/// Format: `AppName/1.0.0+1 (ios 18.3)` or `AppName/1.0.0+1 (android 14)`
class UserAgentInterceptor extends Interceptor {
  final String _userAgent;

  UserAgentInterceptor(this._userAgent);

  /// Build a User-Agent string from app and platform info
  factory UserAgentInterceptor.build({
    required String appName,
    required String version,
    required String buildNumber,
  }) {
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;

    // Extract clean OS version (remove kernel details on Android/Linux)
    final cleanOsVersion = _cleanOsVersion(osVersion);

    return UserAgentInterceptor(
      '$appName/$version+$buildNumber ($os $cleanOsVersion)',
    );
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['User-Agent'] = _userAgent;
    handler.next(options);
  }

  /// Clean up OS version string to keep only the relevant version number
  static String _cleanOsVersion(String osVersion) {
    // On iOS/macOS: "Version 18.3 (Build 22D5055b)" → "18.3"
    final versionMatch = RegExp(r'Version (\S+)').firstMatch(osVersion);
    if (versionMatch != null) {
      return versionMatch.group(1)!;
    }

    // On Android: "Linux 5.10.0 ..." or similar → try to extract SDK version
    // Just return the raw version if no pattern matches
    return osVersion.split(' ').first;
  }
}
