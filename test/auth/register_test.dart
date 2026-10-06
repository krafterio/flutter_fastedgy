/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const account = {'email': 'ada@example.com', 'password': 'secret'};

  late Bus bus;
  late List<AuthLoggedEvent> logged;

  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
    bus = Bus();
    logged = [];
    bus.on<AuthLoggedEvent>().listen(logged.add);
    container.registerSingleton<Bus>(bus);
  });

  tearDown(container.reset);

  DefaultAuthProvider<dynamic> answering(Map<String, Object?> body) =>
      DefaultAuthProvider<dynamic>(
        createMockFetcher(
          (request) => MockResponse.json(body),
          enableAuth: false,
          enableTimezone: false,
          enableRefreshToken: false,
        ),
        const TokenStorage(),
        bus,
      );

  test('creates the account without a session when the server answers with no token', () async {
    final provider = answering({'message': 'User registered successfully'});

    final result = await provider.register(account);
    await pumpEventQueue();

    expect(result.success, isTrue);
    expect(result.accessToken, isNull);
    expect(logged, isEmpty);
    expect(await provider.isAuthenticated(), isFalse);
  });

  test('opens the session when the server answers with tokens', () async {
    final provider = answering({
      'access_token': 'access-1',
      'refresh_token': 'refresh-1',
    });

    final result = await provider.register(account);
    await pumpEventQueue();

    expect(result.accessToken, 'access-1');
    expect(logged, hasLength(1));
    expect(await provider.getRefreshToken(), 'refresh-1');
  });
}
