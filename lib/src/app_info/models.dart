/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Immutable application information loaded once at startup.
///
/// Wraps the relevant fields from `package_info_plus` so that consumers can
/// access version/build/store information synchronously after `initializeFastEdgy`
/// has completed, without depending on `package_info_plus` directly.
///
/// Retrieve it from the container:
/// ```dart
/// final appInfo = getService<AppInfo>();
/// print('Version: ${appInfo.version}+${appInfo.buildNumber}');
/// ```
class AppInfo {
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
  final String? installerStore;
  final String osVersion;

  const AppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
    required this.osVersion,
    this.installerStore,
  });

  /// Load `AppInfo` from the underlying platform via `package_info_plus`.
  static Future<AppInfo> fromPlatform() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(
      appName: info.appName,
      packageName: info.packageName,
      version: devVersion(info.version),
      buildNumber: info.buildNumber,
      installerStore: info.installerStore,
      osVersion: await _osVersion(),
    );
  }

  static Future<String> _osVersion() async {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) {
      return (await deviceInfo.webBrowserInfo).appVersion ?? '';
    }
    if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).systemVersion;
    }
    if (Platform.isAndroid) {
      return (await deviceInfo.androidInfo).version.release;
    }
    if (Platform.isWindows) {
      return windowsVersion(await deviceInfo.windowsInfo);
    }
    final match = RegExp(r'Version (\S+)')
        .firstMatch(Platform.operatingSystemVersion);
    return match?.group(1) ?? Platform.operatingSystemVersion.split(' ').first;
  }

  /// Combined version in the form `"1.2.3+45"`.
  String get fullVersion => '$version+$buildNumber';
}

const _devSuffix = '-dev';

/// The version of the build: a debug build marks it as a semver pre-release,
/// `1.0.0-dev`, the release in development after `1.0.0`. An Android debug
/// build already has it from Gradle and is not marked twice.
@visibleForTesting
String devVersion(String version) => kDebugMode && !version.endsWith(_devSuffix)
    ? '$version$_devSuffix'
    : version;

/// The Windows version in the form `10.0.26200`.
///
/// `Platform.operatingSystemVersion` reads `"Windows 11 Home" 10.0 (Build 26200)`
/// there, which the pattern kept for macOS does not parse: the User-Agent would
/// carry `"Windows` as the version.
@visibleForTesting
String windowsVersion(WindowsDeviceInfo info) =>
    '${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
