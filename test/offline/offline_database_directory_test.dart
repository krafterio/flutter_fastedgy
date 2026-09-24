import 'package:flutter/foundation.dart';
import 'package:flutter_fastedgy/src/offline/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('keeps the Windows database out of the Documents folder', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    expect(offlineDatabaseDirectory(), same(getApplicationSupportDirectory));
  });

  test('leaves the other platforms on the drift default', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;

      expect(offlineDatabaseDirectory(), isNull, reason: platform.name);
    }
  });
}
