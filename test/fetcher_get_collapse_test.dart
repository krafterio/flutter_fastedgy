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

  /// Holds every answer until the test releases it, so the reads below really
  /// are in flight together.
  ({Fetcher fetcher, List<MockRequest> seen, void Function() release})
  heldFetcher(Object body) {
    final seen = <MockRequest>[];
    final gate = Completer<void>();

    final fetcher = createMockFetcher((request) async {
      seen.add(request);
      await gate.future;

      return MockResponse.json(body);
    }, enableAuth: false);

    return (fetcher: fetcher, seen: seen, release: () => gate.complete());
  }

  test(
    'three holders reading the same rows at once open one request',
    () async {
      final held = heldFetcher({
        'items': [
          {'id': 1, 'name': 'Ada'},
        ],
        'total': 1,
      });

      final reads = [
        for (var i = 0; i < 3; i++)
          held.fetcher.get(
            '/acme/users',
            params: {'limit': 50, 'offset': 0},
            headers: {'X-Fields': 'id,name'},
          ),
      ];

      held.release();
      final responses = await Future.wait(reads);

      expect(held.seen, hasLength(1));
      expect(
        responses.map((one) => one.data),
        everyElement({
          'items': [
            {'id': 1, 'name': 'Ada'},
          ],
          'total': 1,
        }),
      );
    },
  );

  test('each holder gets its own copy of the shared body', () async {
    final held = heldFetcher({
      'items': [
        {'id': 1, 'name': 'Ada'},
      ],
    });

    final first = held.fetcher.get('/acme/users');
    final second = held.fetcher.get('/acme/users');

    held.release();
    final one = (await first).data as Map<String, dynamic>;
    final two = (await second).data as Map<String, dynamic>;

    (one['items'] as List).cast<Map<String, dynamic>>().first['name'] = 'Grace';

    expect(
      (two['items'] as List).cast<Map<String, dynamic>>().first['name'],
      'Ada',
    );
  });

  test(
    'two reads of the same path under different headers stay apart',
    () async {
      final held = heldFetcher({'items': [], 'total': 0});

      final reads = [
        held.fetcher.get('/acme/flows', headers: {'X-Filter': '["id","=",1]'}),
        held.fetcher.get('/acme/flows', headers: {'X-Filter': '["id","=",2]'}),
      ];

      held.release();
      await Future.wait(reads);

      expect(held.seen, hasLength(2));
    },
  );

  test('a separator inside a header value never joins two reads', () async {
    final held = heldFetcher({'items': [], 'total': 0});

    final reads = [
      held.fetcher.get(
        '/acme/flows',
        headers: {'X-Fields': 'id', 'X-Filter': '["id","=",1]'},
      ),
      // Reads as the pair above once flattened onto one line.
      held.fetcher.get(
        '/acme/flows',
        headers: {'X-Fields': 'id&X-Filter=["id","=",1]'},
      ),
    ];

    held.release();
    await Future.wait(reads);

    expect(held.seen, hasLength(2));
  });

  test('a read that settled is not answered from the collapse', () async {
    final seen = <MockRequest>[];
    final fetcher = createMockFetcher((request) {
      seen.add(request);

      return const MockResponse.json({'items': []});
    }, enableAuth: false);

    await fetcher.get('/acme/users');
    await fetcher.get('/acme/users');

    expect(seen, hasLength(2));
  });

  test('a cancellable read is never shared', () async {
    final held = heldFetcher({'items': []});

    final reads = [
      held.fetcher.get('/acme/users', id: 'picker'),
      held.fetcher.get('/acme/users', id: 'picker'),
    ];

    held.release();
    await Future.wait(reads);

    expect(held.seen, hasLength(2));
  });

  test('a refusal reaches every holder riding the request', () async {
    final seen = <MockRequest>[];
    final gate = Completer<void>();
    final fetcher = createMockFetcher((request) async {
      seen.add(request);
      await gate.future;

      return const MockResponse.error(500, body: {'detail': 'Boom'});
    }, enableAuth: false);

    // Matchers attached before the gate opens: a future left without a listener
    // over a microtask drain reports its failure as uncaught.
    final settled = [
      for (var i = 0; i < 2; i++)
        expectLater(fetcher.get('/acme/users'), throwsA(isA<HttpError>())),
    ];

    gate.complete();
    await Future.wait(settled);

    expect(seen, hasLength(1));

    // The entry is gone with the failure: the next read goes out on its own.
    await expectLater(fetcher.get('/acme/users'), throwsA(isA<HttpError>()));
    expect(seen, hasLength(2));
  });
}
