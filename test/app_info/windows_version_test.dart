import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_fastedgy/src/app_info/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the Windows version as numbers, not from the product name', () {
    final info = WindowsDeviceInfo(
      computerName: 'DESKTOP',
      numberOfCores: 8,
      systemMemoryInMegabytes: 16384,
      userName: 'user',
      majorVersion: 10,
      minorVersion: 0,
      buildNumber: 26200,
      platformId: 2,
      csdVersion: '',
      servicePackMajor: 0,
      servicePackMinor: 0,
      suitMask: 256,
      productType: 1,
      reserved: 0,
      buildLab: '',
      buildLabEx: '',
      digitalProductId: Uint8List(0),
      displayVersion: '25H2',
      editionId: 'Core',
      installDate: DateTime(2026),
      productId: '',
      productName: 'Windows 11 Famille',
      registeredOwner: 'user',
      releaseId: '2009',
      deviceId: '',
    );

    expect(windowsVersion(info), '10.0.26200');
  });
}
