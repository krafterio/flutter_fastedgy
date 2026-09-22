/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  tearDown(container.reset);

  /// Answers a path once the test releases it; [seen] lists what reached the
  /// transport, in order.
  ({Fetcher fetcher, List<String> seen, void Function(String path) release})
  heldFetcher() {
    final seen = <String>[];
    final gates = <String, Completer<void>>{};

    final fetcher = createMockFetcher((request) async {
      seen.add(request.path);
      await (gates[request.path] ??= Completer<void>()).future;

      return const MockResponse.json({'ok': true});
    }, enableAuth: false);

    return (
      fetcher: fetcher,
      seen: seen,
      release: (path) => (gates[path] ??= Completer<void>()).complete(),
    );
  }

  test('a background request waits for the usage ones in flight', () async {
    final held = heldFetcher();
    final usage = held.fetcher.get('/usage');
    await pumpEventQueue();

    final background = Fetcher.background(() => held.fetcher.get('/sync'));
    await pumpEventQueue();

    expect(held.seen, ['/usage']);

    held
      ..release('/usage')
      ..release('/sync');
    await Future.wait([usage, background]);

    expect(held.seen, ['/usage', '/sync']);
  });

  test('a usage request never waits for a background one', () async {
    final held = heldFetcher();
    final background = Fetcher.background(() => held.fetcher.get('/sync'));
    await pumpEventQueue();

    final usage = held.fetcher.get('/usage');
    await pumpEventQueue();

    expect(held.seen, ['/sync', '/usage']);

    held
      ..release('/sync')
      ..release('/usage');
    await Future.wait([background, usage]);
  });

  test('the usage of every fetcher counts', () async {
    final screen = heldFetcher();
    final mirror = heldFetcher();
    final usage = screen.fetcher.get('/usage');
    await pumpEventQueue();

    final background = Fetcher.background(() => mirror.fetcher.get('/sync'));
    await pumpEventQueue();

    expect(mirror.seen, isEmpty);

    screen.release('/usage');
    mirror.release('/sync');
    await Future.wait([usage, background]);

    expect(mirror.seen, ['/sync']);
  });

  test(
    'what everybody waits on goes at once, even asked in the background',
    () async {
      final held = heldFetcher();
      final usage = held.fetcher.get('/usage');
      await pumpEventQueue();

      final refresh = Fetcher.background(
        () => Fetcher.foreground(() => held.fetcher.post('/auth/refresh', {})),
      );
      await pumpEventQueue();

      expect(held.seen, ['/usage', '/auth/refresh']);

      held
        ..release('/usage')
        ..release('/auth/refresh');
      await Future.wait([usage, refresh]);
    },
  );

  test('a usage read never rides a background read that waits', () async {
    final held = heldFetcher();
    final usage = held.fetcher.get('/usage');
    await pumpEventQueue();

    final background = Fetcher.background(() => held.fetcher.get('/rows'));
    final read = held.fetcher.get('/rows');
    await pumpEventQueue();

    expect(held.seen, ['/usage', '/rows']);

    held
      ..release('/usage')
      ..release('/rows');
    await Future.wait([usage, background, read]);

    expect(held.seen, ['/usage', '/rows', '/rows']);
  });

  test('reads made for two tenants never share an answer', () async {
    final held = heldFetcher();
    final reads = [
      for (final workspace in ['acme', 'studio'])
        OfflineContextParams.within({
          'workspace': workspace,
        }, () => held.fetcher.get('/rows')),
    ];
    await pumpEventQueue();

    expect(held.seen, ['/rows', '/rows']);

    held.release('/rows');
    await Future.wait(reads);
  });
}
