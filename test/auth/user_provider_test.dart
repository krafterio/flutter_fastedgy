/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Bus bus;

  setUp(() {
    initializeContainer();

    if (hasService<Bus>()) {
      container.unregister<Bus>();
    }

    bus = Bus();
    container.registerSingleton<Bus>(bus);
  });

  tearDown(container.reset);

  group('UserProvider', () {
    test('serves concurrent callers from one load', () async {
      var calls = 0;
      final gate = Completer<void>();
      final users = UserProvider<String>(() async {
        calls++;
        await gate.future;

        return 'ada';
      });

      final loads = Future.wait([users.load(), users.load(), users.load()]);
      expect(users.loading, isTrue);
      gate.complete();

      expect(await loads, ['ada', 'ada', 'ada']);
      expect(calls, 1);
      expect(users.user, 'ada');
      expect(users.loading, isFalse);
    });

    test('serves the held user without hitting the loader again', () async {
      var calls = 0;
      final users = UserProvider<String>(() async {
        calls++;

        return 'ada';
      });

      await users.load();
      await users.load();

      expect(calls, 1);
    });

    test('refresh reloads a user already held', () async {
      var calls = 0;
      final users = UserProvider<String>(() async => 'ada-${++calls}');

      await users.load();

      expect(await users.refresh(), 'ada-2');
      expect(users.user, 'ada-2');
    });

    test('loads again after a failed attempt', () async {
      var fail = true;
      final users = UserProvider<String>(() async {
        if (fail) {
          throw StateError('offline');
        }

        return 'ada';
      });

      await expectLater(users.load(), throwsStateError);
      expect(users.error, isA<StateError>());

      fail = false;

      expect(await users.load(), 'ada');
      expect(users.error, isNull);
    });

    test('notifies its listeners on load, adopt and clear', () async {
      final users = UserProvider<String>(() async => 'ada');
      var notifications = 0;
      users.addListener(() => notifications++);

      await users.load();
      expect(notifications, 1);

      users.adopt('grace');
      expect(users.user, 'grace');
      expect(notifications, 2);

      users.clear();
      expect(users.user, isNull);
      expect(notifications, 3);
    });

    test('drops a user that lands after a logout', () async {
      final gate = Completer<void>();
      final users = UserProvider<String>(() async {
        await gate.future;

        return 'ada';
      });

      final load = users.load();
      bus.fire(const AuthLogoutEvent());
      // The bus delivers asynchronously: let the logout land before the
      // loader answers, which is the race being guarded.
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await load;

      expect(users.user, isNull);
      expect(users.isLoaded, isFalse);
    });
  });
}
