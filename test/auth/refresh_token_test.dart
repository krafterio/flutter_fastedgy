/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwtExpiringAt(DateTime when) {
  final payload = base64Url
      .encode(
        utf8.encode(jsonEncode({'exp': when.millisecondsSinceEpoch ~/ 1000})),
      )
      .replaceAll('=', '');

  return 'header.$payload.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RefreshTokenLock', () {
    test(
      'settles a queued request whose token was cancelled while waiting',
      () async {
        final provider = _GatedAuthProvider();
        final lock = RefreshTokenLock(provider);

        final first = lock.refreshToken();
        final cancelled = CancelToken();
        final queuedCancelled = lock.refreshToken(cancelToken: cancelled);
        final queued = lock.refreshToken(cancelToken: CancelToken());

        cancelled.cancel();
        provider.gate.complete(true);

        expect(await first, isTrue);
        expect(
          await queuedCancelled.timeout(const Duration(seconds: 1)),
          isFalse,
        );
        expect(await queued.timeout(const Duration(seconds: 1)), isTrue);
      },
    );

    test(
      'settles a request already cancelled when the next refresh starts',
      () async {
        final provider = _GatedAuthProvider();
        final lock = RefreshTokenLock(provider);

        final cancelled = CancelToken()..cancel();
        final queued = lock.waitForRefresh(cancelled);

        final refresh = lock.triggerRefresh();
        provider.gate.complete(true);

        expect(await refresh, isTrue);
        expect(await queued.timeout(const Duration(seconds: 1)), isFalse);
      },
    );
  });

  group('DefaultAuthProvider single-flight', () {
    late Completer<void> gate;
    late int calls;
    late Fetcher fetcher;

    setUp(() {
      initializeContainer();

      if (!hasService<Bus>()) {
        container.registerSingleton<Bus>(Bus());
      }

      SharedPreferences.setMockInitialValues({
        'token': _jwtExpiringAt(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        'refresh_token': 'refresh-1',
      });

      gate = Completer<void>();
      calls = 0;
      fetcher = createMockFetcher(
        (request) async {
          calls++;
          await gate.future;

          return MockResponse.json({
            'access_token': _jwtExpiringAt(
              DateTime.now().add(const Duration(minutes: 15)),
            ),
            'refresh_token': 'refresh-2',
          });
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      );
    });

    tearDown(container.reset);

    DefaultAuthProvider<dynamic> buildProvider() =>
        DefaultAuthProvider<dynamic>(fetcher, TokenStorage(), Bus());

    test(
      'shares one /auth/refresh between the HTTP path and a socket handshake',
      () async {
        final provider = buildProvider();

        final http = provider.refreshToken();
        final handshake = provider.getValidatedAccessToken();

        await pumpEventQueue();
        gate.complete();

        expect(await http, isTrue);
        expect(await handshake, await provider.getAccessToken());
        expect(calls, 1);
      },
    );

    test('refreshes again once the in-flight call is done', () async {
      final provider = buildProvider();

      gate.complete();
      expect(await provider.refreshToken(), isTrue);
      expect(await provider.refreshToken(), isTrue);
      expect(calls, 2);
    });
  });

  group('RefreshTokenInterceptor', () {
    late int protectedCalls;
    late _RenewingAuthProvider provider;
    late Fetcher fetcher;

    setUp(() {
      initializeContainer();

      if (!hasService<Bus>()) {
        container.registerSingleton<Bus>(Bus());
      }

      SharedPreferences.setMockInitialValues({
        'token': _jwtExpiringAt(
          DateTime.now().add(const Duration(minutes: 15)),
        ),
        'refresh_token': 'refresh-1',
      });

      provider = _RenewingAuthProvider();
      container.registerSingleton<TokenStorage>(TokenStorage());
      container.registerSingleton<AuthProvider<dynamic>>(provider);

      protectedCalls = 0;
      fetcher = createMockFetcher((request) {
        protectedCalls++;

        // Answers 401 whatever the token is, the way an endpoint refusing on
        // something a refresh cannot fix does. Capped so a looping interceptor
        // fails the expectation instead of hanging the suite.
        if (protectedCalls > 5) {
          return const MockResponse.error(500);
        }

        return const MockResponse.error(401);
      });
    });

    tearDown(container.reset);

    test(
      'replays a request once, not for as long as the refresh works',
      () async {
        await expectLater(
          fetcher.get('/api/protected'),
          throwsA(isA<Exception>()),
        );

        expect(protectedCalls, 2);
        expect(provider.refreshes, 1);
      },
    );

    test(
      'still refreshes for a resource whose name starts like auth',
      () async {
        await expectLater(
          fetcher.get('/api/authors'),
          throwsA(isA<Exception>()),
        );

        expect(provider.refreshes, 1);
      },
    );

    test('never refreshes on a rejected login', () async {
      await expectLater(
        fetcher.post('/auth/token', {'username': 'ada', 'password': 'wrong'}),
        throwsA(isA<Exception>()),
      );

      expect(provider.refreshes, 0);
    });
  });
}

class _RenewingAuthProvider implements AuthProvider<dynamic> {
  var refreshes = 0;

  @override
  Future<bool> refreshToken() async {
    refreshes++;
    await getService<TokenStorage>().saveAccessToken(
      _jwtExpiringAt(DateTime.now().add(const Duration(minutes: 15))),
    );

    return true;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthResult<dynamic>> login(String username, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthResult<dynamic>> register(Map<String, dynamic> userData) =>
      throw UnimplementedError();

  @override
  Future<String?> getAccessToken() => throw UnimplementedError();

  @override
  Future<String?> getValidatedAccessToken() => throw UnimplementedError();

  @override
  Future<String?> getRefreshToken() => throw UnimplementedError();

  @override
  Future<bool> isAuthenticated() => throw UnimplementedError();

  @override
  Future<dynamic> getCurrentUser() => throw UnimplementedError();
}

class _GatedAuthProvider implements AuthProvider<dynamic> {
  final gate = Completer<bool>();

  @override
  Future<bool> refreshToken() => gate.future;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthResult<dynamic>> login(String username, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthResult<dynamic>> register(Map<String, dynamic> userData) =>
      throw UnimplementedError();

  @override
  Future<String?> getAccessToken() => throw UnimplementedError();

  @override
  Future<String?> getValidatedAccessToken() => throw UnimplementedError();

  @override
  Future<String?> getRefreshToken() => throw UnimplementedError();

  @override
  Future<bool> isAuthenticated() => throw UnimplementedError();

  @override
  Future<dynamic> getCurrentUser() => throw UnimplementedError();
}
