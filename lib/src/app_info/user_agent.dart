/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'models.dart';

/// The application User-Agent, built once from [AppInfo] + platform info.
///
/// Standalone service (registered in the container) so any transport can send the
/// same header: Dio requests get it via `UserAgentInterceptor`, other transports
/// (e.g. a raw WebSocket handshake) read [value] and set the header themselves.
///
/// Retrieve it from the container:
/// ```dart
/// final ua = getService<UserAgent>().value;
/// ```
///
/// Format: `AppName/1.0.0+1 (ios 18.3; appstore)`.
class UserAgent {
  /// The built User-Agent string.
  final String value;

  const UserAgent(this.value);

  /// Build from [AppInfo] and the current platform (OS + cleaned OS version).
  factory UserAgent.fromAppInfo(AppInfo appInfo) {
    final os = Platform.operatingSystem;
    final storeSuffix =
        (appInfo.installerStore != null && appInfo.installerStore!.isNotEmpty)
        ? '; ${appInfo.installerStore}'
        : '';
    return UserAgent(
      '${appInfo.appName}/${appInfo.version}+${appInfo.buildNumber} ($os ${appInfo.osVersion}$storeSuffix)',
    );
  }

  @override
  String toString() => value;
}
