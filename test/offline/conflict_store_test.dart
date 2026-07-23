/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

ConflictEntry _entry(String basePath, Object recordId, String createdAt) =>
    ConflictEntry(
      basePath: basePath,
      recordId: recordId,
      mine: {'name': 'Mine'},
      base: {'name': 'Base'},
      server: {'id': recordId, 'name': 'Theirs'},
      fields: const ['name'],
      createdAt: createdAt,
      cache: const OutboxCacheContext(kind: 'json', namespace: '/items'),
    );

void main() {
  late DriftLocalStore store;

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
  });

  tearDown(() => store.close());

  test('park stores an entry, get and all read it back newest-first', () async {
    final conflicts = ConflictStore(store);

    await conflicts.park(_entry('/items', 1, '2026-07-20T10:00:00Z'));
    await conflicts.park(_entry('/items', 2, '2026-07-22T10:00:00Z'));

    final all = await conflicts.all();
    expect(all.map((e) => e.recordId), [2, 1]);

    final one = await conflicts.get('/items', 1);
    expect(one?.server['name'], 'Theirs');
    expect(one?.fields, ['name']);
  });

  test(
    'a re-conflict on the same record overwrites rather than stacks',
    () async {
      final conflicts = ConflictStore(store);

      await conflicts.park(_entry('/items', 1, '2026-07-20T10:00:00Z'));
      await conflicts.park(_entry('/items', 1, '2026-07-22T10:00:00Z'));

      final all = await conflicts.all();
      expect(all, hasLength(1));
      expect(all.single.createdAt, '2026-07-22T10:00:00Z');
    },
  );

  test('resolve removes the entry', () async {
    final conflicts = ConflictStore(store);
    await conflicts.park(_entry('/items', 1, '2026-07-20T10:00:00Z'));

    await conflicts.resolve('/items', 1);

    expect(await conflicts.all(), isEmpty);
    expect(await conflicts.get('/items', 1), isNull);
  });

  test('onChanged reports the count on park and resolve', () async {
    final counts = <int>[];
    final conflicts = ConflictStore(store, onChanged: counts.add);

    await conflicts.park(_entry('/items', 1, '2026-07-20T10:00:00Z'));
    await conflicts.park(_entry('/items', 2, '2026-07-22T10:00:00Z'));
    await conflicts.resolve('/items', 1);

    expect(counts, [1, 2, 1]);
  });
}
