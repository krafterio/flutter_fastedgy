/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// The shape that made a whole feature look empty offline: favourites carrying
/// a `user` the reads never asked for, and the projects reaching them through
/// their reverse relation.
const _schema = LocalSchema({
  'project': LocalModelSchema(
    name: 'project',
    apiName: 'projects',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'favorites': LocalFieldSchema(
        name: 'favorites',
        type: 'one2many',
        target: 'project_user_favorite',
      ),
    },
  ),
  'project_user_favorite': LocalModelSchema(
    name: 'project_user_favorite',
    apiName: 'project_user_favorites',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'sequence': LocalFieldSchema(name: 'sequence', type: 'integer'),
      'user': LocalFieldSchema(name: 'user', type: 'many2one', target: 'user'),
      'project': LocalFieldSchema(
        name: 'project',
        type: 'many2one',
        target: 'project',
      ),
    },
  ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReplicaStore store;
  late List<LogRecord> warnings;
  late StreamSubscription<LogRecord> logs;

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    store = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();

    for (final model in _schema.models.values) {
      await store.ensureModel(model);
    }

    warnings = [];
    logs = Logger.root.onRecord.listen((record) {
      if (record.level >= Level.WARNING) {
        warnings.add(record);
      }
    });
  });

  tearDown(() async {
    await logs.cancel();
    await store.close();
  });

  final favorites = _schema.models['project_user_favorite']!;

  group('empty offline result diagnosis', () {
    test('names a filtered field the reads never brought back', () async {
      // Mirrored through X-Fields that omitted `user`, as a screen would.
      await store.upsertAll(favorites, '1', [
        {'id': 4, 'sequence': 0, 'project': 11},
        {'id': 3, 'sequence': 1, 'project': 10},
      ]);

      final result = await store.query(
        _schema,
        'project_user_favorite',
        scope: '1',
        filter: ['user', '=', 2],
      );

      expect(result.total, 0);
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('user'));
      expect(warnings.single.message, contains('never mirrored'));
    });

    test('says nothing when the filtered field is mirrored', () async {
      await store.upsertAll(favorites, '1', [
        {'id': 4, 'sequence': 0, 'user': 2, 'project': 11},
      ]);

      final result = await store.query(
        _schema,
        'project_user_favorite',
        scope: '1',
        // A legitimate miss: the column holds values, just not this one.
        filter: ['user', '=', 99],
      );

      expect(result.total, 0);
      expect(warnings, isEmpty);
    });

    test('says nothing when the scope holds no row at all', () async {
      final result = await store.query(
        _schema,
        'project_user_favorite',
        scope: '1',
        filter: ['user', '=', 2],
      );

      // Nothing mirrored yet is not the same fault, and saying so would cry
      // wolf on every first launch.
      expect(result.total, 0);
      expect(warnings, isEmpty);
    });

    test('follows a relation hop', () async {
      await store.upsertAll(_schema.models['project']!, '1', [
        {'id': 11, 'name': 'Kascade'},
      ]);
      await store.upsertAll(favorites, '1', [
        {'id': 4, 'sequence': 0, 'project': 11},
      ]);

      final result = await store.query(
        _schema,
        'project',
        scope: '1',
        filter: ['favorites.user', '=', 2],
      );

      expect(result.total, 0);
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('favorites.user'));
    });

    test('covers order_by too', () async {
      await store.upsertAll(favorites, '1', [
        {'id': 4, 'user': 2, 'project': 11},
      ]);

      // `sequence` was never mirrored, so ordering on it is silently arbitrary.
      final result = await store.query(
        _schema,
        'project_user_favorite',
        scope: '1',
        filter: ['user', '=', 99],
        orderBy: ['sequence'],
      );

      expect(result.total, 0);
      expect(warnings.single.message, contains('sequence'));
    });

    test('stays quiet on a query with no filter', () async {
      await store.upsertAll(favorites, '1', [
        {'id': 4, 'sequence': 0, 'project': 11},
      ]);

      await store.query(_schema, 'project_user_favorite', scope: '2');

      expect(warnings, isEmpty);
    });
  });

  group('field path resolution', () {
    test('resolves a direct column and a relation hop', () {
      expect(resolveQueryColumn(_schema, 'project_user_favorite', 'user'), (
        model: 'project_user_favorite',
        column: 'user',
      ));
      expect(resolveQueryColumn(_schema, 'project', 'favorites.user'), (
        model: 'project_user_favorite',
        column: 'user',
      ));
    });

    test('returns null for what names no stored column', () {
      expect(resolveQueryColumn(_schema, 'project', 'favorites'), isNull);
      expect(resolveQueryColumn(_schema, 'project', 'unknown'), isNull);
      expect(resolveQueryColumn(_schema, 'project', 'a.b.c'), isNull);
      expect(resolveQueryColumn(_schema, 'nope', 'name'), isNull);
    });
  });

  group('field path extraction', () {
    test('collects every field a nested filter reads', () {
      final filter = parseFilter([
        '&',
        [
          ['user', '=', 2],
          [
            '|',
            [
              ['sequence', '>', 1],
              ['project', '=', 11],
            ],
          ],
        ],
      ]);

      expect(filterFieldPaths(filter), {'user', 'sequence', 'project'});
    });

    test('descends into the sub-filter of an any rule', () {
      final filter = parseFilter([
        '&',
        [
          ['name', '=', 'Trip'],
          [
            'favorites',
            'any',
            [
              '&',
              [
                ['user', '=', 2],
                ['sequence', '>', 1],
              ],
            ],
          ],
        ],
      ]);

      expect(filterFieldPaths(filter), {
        'name',
        'favorites',
        'favorites.user',
        'favorites.sequence',
      });
    });

    test('strips the direction from an order_by', () {
      expect(orderByFieldPaths(['-sequence', 'name:asc']), {
        'sequence',
        'name',
      });
      expect(orderByFieldPaths('name'), {'name'});
      expect(orderByFieldPaths(null), isEmpty);
    });
  });
}
