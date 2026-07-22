/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  late DriftLocalStore store;

  setUp(() async {
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
  });

  tearDown(() => store.close());

  group('DriftLocalStore', () {
    test('round-trips a record', () async {
      await store.put('/users', 1, {'id': 1, 'name': 'Ada'});

      final record = await store.get('/users', 1);

      expect(record, {'id': 1, 'name': 'Ada'});
    });

    test('returns null for a missing record', () async {
      expect(await store.get('/users', 99), isNull);
    });

    test('accepts string and int ids interchangeably', () async {
      await store.put('/users', '7', {'id': 7});

      expect(await store.get('/users', 7), isNotNull);
    });

    test('putAll merges records', () async {
      await store.put('/users', 1, {'id': 1, 'name': 'Ada'});
      await store.putAll('/users', {
        '2': {'id': 2, 'name': 'Grace'},
        '3': {'id': 3, 'name': 'Edsger'},
      });

      expect(await store.getAll('/users'), hasLength(3));
    });

    test('replaceAll prunes absent records', () async {
      await store.putAll('/users', {
        '1': {'id': 1},
        '2': {'id': 2},
      });
      await store.replaceAll('/users', {
        '2': {'id': 2, 'name': 'Grace'},
      });

      final records = await store.getAll('/users');

      expect(records, hasLength(1));
      expect(records.single['id'], 2);
    });

    test('delete removes a single record', () async {
      await store.putAll('/users', {
        '1': {'id': 1},
        '2': {'id': 2},
      });
      await store.delete('/users', 1);

      expect(await store.get('/users', 1), isNull);
      expect(await store.get('/users', 2), isNotNull);
    });

    test('clear empties a single namespace', () async {
      await store.put('/users', 1, {'id': 1});
      await store.put('/tasks', 1, {'id': 1});
      await store.clear('/users');

      expect(await store.getAll('/users'), isEmpty);
      expect(await store.getAll('/tasks'), hasLength(1));
    });

    test('clearAll empties every namespace', () async {
      await store.put('/users', 1, {'id': 1});
      await store.put('/tasks', 1, {'id': 1});
      await store.clearAll();

      expect(await store.getAll('/users'), isEmpty);
      expect(await store.getAll('/tasks'), isEmpty);
    });

    test('preserves nested relations and lists', () async {
      final record = {
        'id': 1,
        'user': {'id': 5, 'name': 'Ada'},
        'tags': ['a', 'b'],
      };
      await store.put('/memberships', 1, record);

      expect(await store.get('/memberships', 1), record);
    });
  });
}
