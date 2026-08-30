/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnreadableSecureStoragePlatform
    extends TestFlutterSecureStoragePlatform {
  _UnreadableSecureStoragePlatform() : super(<String, String>{});

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => throw Exception('keystore key invalidated');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secure;

  setUp(() {
    secure = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      secure,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('reads and writes the secure storage', () async {
    const storage = TokenStorage();

    await storage.saveAccessToken('access');
    await storage.saveRefreshToken('refresh');

    expect(secure['token'], 'access');
    expect(await storage.getAccessToken(), 'access');
    expect(await storage.getRefreshToken(), 'refresh');
  });

  test('ignores the shared preferences without the legacy mode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'token': 'access',
      'refresh_token': 'refresh',
    });

    const storage = TokenStorage();

    expect(await storage.getAccessToken(), isNull);
    expect(await storage.getRefreshToken(), isNull);
  });

  test('moves the shared preferences tokens to the secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'token': 'access',
      'refresh_token': 'refresh',
    });

    const storage = TokenStorage(legacy: true);

    expect(await storage.getAccessToken(), 'access');
    expect(await storage.getRefreshToken(), 'refresh');
    expect(secure['token'], 'access');
    expect(secure['refresh_token'], 'refresh');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
  });

  test('keeps the secure storage token over the legacy one', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'token': 'legacy'});
    secure['token'] = 'secure';

    const storage = TokenStorage(legacy: true);

    expect(await storage.getAccessToken(), 'secure');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token'), 'legacy');
  });

  test('clears both storages on logout', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'token': 'legacy'});
    secure['token'] = 'secure';
    secure['refresh_token'] = 'refresh';

    await const TokenStorage(legacy: true).clearTokens();

    expect(secure, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token'), isNull);
  });

  test(
    'answers an empty session when the secure storage is unreadable',
    () async {
      FlutterSecureStoragePlatform.instance =
          _UnreadableSecureStoragePlatform();

      expect(await const TokenStorage().getAccessToken(), isNull);
      expect(await const TokenStorage().isAuthenticated(), isFalse);
    },
  );
}
