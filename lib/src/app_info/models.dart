/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

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
      version: info.version,
      buildNumber: info.buildNumber,
      installerStore: info.installerStore,
      osVersion: await _osVersion(),
    );
  }

  static Future<String> _osVersion() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).systemVersion;
    }
    if (Platform.isAndroid) {
      return (await deviceInfo.androidInfo).version.release;
    }
    final match = RegExp(r'Version (\S+)')
        .firstMatch(Platform.operatingSystemVersion);
    return match?.group(1) ?? Platform.operatingSystemVersion.split(' ').first;
  }

  /// Combined version in the form `"1.2.3+45"`.
  String get fullVersion => '$version+$buildNumber';
}
