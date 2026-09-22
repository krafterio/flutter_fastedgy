/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// `user` is in the schema (every metadata model is) but never mirrored: its
/// table does not exist locally, as for an app that only syncs the members.
const _schema = LocalSchema({
  'user': LocalModelSchema(
    name: 'user',
    apiName: 'users',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
    },
  ),
  'task_category': LocalModelSchema(
    name: 'task_category',
    apiName: 'task_categories',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
    },
  ),
  'task': LocalModelSchema(
    name: 'task',
    apiName: 'tasks',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'checked': LocalFieldSchema(name: 'checked', type: 'boolean'),
      'users': LocalFieldSchema(
        name: 'users',
        type: 'many2many',
        target: 'user',
      ),
      'task_category': LocalFieldSchema(
        name: 'task_category',
        type: 'many2one',
        target: 'task_category',
      ),
    },
  ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReplicaStore store;

  Future<List<Object?>> names(dynamic filter) async {
    final result = await store.query(
      _schema,
      'task',
      scope: 'acme',
      filter: filter,
    );

    return result.records.map((r) => r['name']).toList();
  }

  setUp(() async {
    store = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    await store.ensureModel(_schema.models['task_category']!);
    await store.ensureModel(_schema.models['task']!);

    await store.replaceScope(_schema.models['task_category']!, 'acme', [
      {'id': 1, 'name': 'Maison'},
    ]);
    await store.replaceScope(_schema.models['task']!, 'acme', [
      {
        'id': 1,
        'name': 'Mine',
        'checked': false,
        'users': [
          {'id': 7, 'name': 'Me'},
        ],
        'task_category': {'id': 1},
      },
      {
        'id': 2,
        'name': 'Theirs',
        'checked': false,
        'users': [
          {'id': 8, 'name': 'Other'},
        ],
        'task_category': null,
      },
      {
        'id': 3,
        'name': 'Nobody',
        'checked': true,
        'users': <Map<String, dynamic>>[],
        'task_category': {'id': 1},
      },
    ]);
  });

  tearDown(() => store.close());

  test('users.id reads the pivot without the target table', () async {
    expect(
      await names([
        '&',
        [
          [
            'users.id',
            'in',
            [7],
          ],
          ['checked', 'is false'],
        ],
      ]),
      ['Mine'],
    );
    expect(await names(['users.id', '=', 8]), ['Theirs']);
  });

  test('any / not any without a sub-filter read the pivot alone', () async {
    expect(await names(['users', 'any']), ['Mine', 'Theirs']);
    expect(await names(['users', 'not any']), ['Nobody']);
  });

  test('a m2o filter and its emptiness', () async {
    expect(await names(['task_category', '=', 1]), ['Mine', 'Nobody']);
    expect(await names(['task_category', 'is empty']), ['Theirs']);
  });

  test('a leaf other than the id still needs the target table', () async {
    await expectLater(names(['users.name', '=', 'Me']), throwsA(anything));
  });
}
