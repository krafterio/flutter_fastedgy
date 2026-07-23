/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

// Mirrors the real metadata shape: the server exposes the fulltext field in
// `fields` (it is filterable) with type `fulltext`, while `project` covers
// models whose metadata would omit it.
const _task = LocalModelSchema(
  name: 'task',
  apiName: 'tasks',
  fields: {
    'id': LocalFieldSchema(name: 'id', type: 'integer'),
    'name': LocalFieldSchema(name: 'name', type: 'char'),
    'description': LocalFieldSchema(name: 'description', type: 'text'),
    'email': LocalFieldSchema(name: 'email', type: 'email'),
    'search_value': LocalFieldSchema(name: 'search_value', type: 'fulltext'),
    'project': LocalFieldSchema(
      name: 'project',
      type: 'many2one',
      target: 'project',
    ),
  },
  searchField: 'search_value',
  searchWeights: {'name': 'a', 'description': 'b', 'email': 'd'},
);

const _project = LocalModelSchema(
  name: 'project',
  apiName: 'projects',
  fields: {
    'id': LocalFieldSchema(name: 'id', type: 'integer'),
    'name': LocalFieldSchema(name: 'name', type: 'char'),
    'tasks': LocalFieldSchema(name: 'tasks', type: 'one2many', target: 'task'),
  },
  searchField: 'search_value',
  searchWeights: {'name': 'a'},
);

const _schema = LocalSchema({'task': _task, 'project': _project});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineDatabase db;
  late ReplicaStore store;

  Future<List<Object?>> search(
    String model,
    dynamic filter, {
    dynamic orderBy,
  }) async {
    final result = await store.query(
      _schema,
      model,
      scope: 'acme',
      filter: filter,
      orderBy: orderBy,
    );

    return result.records.map((record) => record['id']).toList();
  }

  Future<void> seed() async {
    await store.ensureModel(_task);
    await store.ensureModel(_project);
    await store.replaceScope(_project, 'acme', [
      {'id': 1, 'name': 'Krafter'},
      {'id': 2, 'name': 'Interne'},
    ]);
    await store.replaceScope(_task, 'acme', [
      {
        'id': 1,
        'name': 'Réunion générale',
        'description': 'notes sur le projet alpha',
        'email': 'ada@x.io',
        'project': {'id': 1},
      },
      {
        'id': 2,
        'name': 'Course à pied',
        'description': 'préparer le marathon',
        'email': null,
        'project': {'id': 2},
      },
      {
        'id': 3,
        'name': 'projet',
        'description': null,
        'email': null,
        'project': null,
      },
    ]);
    await store.replaceScope(_task, 'globex', [
      {'id': 9, 'name': 'Réunion secrète', 'description': null, 'email': null},
    ]);
  }

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    db = OfflineDatabase(NativeDatabase.memory());
    store = ReplicaStore(databaseOpener: () => db);
    await store.open();
  });

  tearDown(() => store.close());

  group('search operator', () {
    setUp(seed);

    test('materializes no physical column for the fulltext field', () async {
      final columns = (await db.customSelect('PRAGMA table_info("task")').get())
          .map((row) => row.read<String>('name'))
          .toList();

      expect(columns, isNot(contains('search_value')));
      expect(columns, contains('search_value_fts_a'));
      expect(columns, contains('search_value_fts_d'));
    });

    test('is accent and case insensitive, confined to the scope', () async {
      expect(await search('task', ['search_value', 'search', 'REUNION']), [1]);
      expect(await search('task', ['search_value', 'search', 'générale']), [1]);
    });

    test('matches by prefix like the server parser', () async {
      expect(await search('task', ['search_value', 'search', 'marath']), [2]);
    });

    test('ORs bare words and ANDs +mandatory terms', () async {
      expect(
        await search('task', ['search_value', 'search', 'marathon projet']),
        unorderedEquals([1, 2, 3]),
      );
      expect(
        await search('task', ['search_value', 'search', 'projet +alpha']),
        [1],
      );
    });

    test('excludes -terms', () async {
      expect(
        await search('task', ['search_value', 'search', 'projet -alpha']),
        [3],
      );
    });

    test('matches quoted phrases exactly', () async {
      expect(
        await search('task', ['search_value', 'search', '"projet alpha"']),
        [1],
      );
      expect(
        await search('task', ['search_value', 'search', '"alpha projet"']),
        isEmpty,
      );
    });

    test('indexes every weight class', () async {
      expect(await search('task', ['search_value', 'search', 'ada']), [1]);
    });

    test('search_fuzzy degrades to search', () async {
      expect(
        await search('task', ['search_value', 'search_fuzzy', 'reunion']),
        [1],
      );
    });

    test('combines with regular rules and follows relation paths', () async {
      expect(
        await search('task', [
          ['search_value', 'search', 'projet'],
          ['email', 'is not empty'],
        ]),
        [1],
      );
      expect(
        await search('task', ['project.search_value', 'search', 'krafter']),
        [1],
      );
      expect(
        await search('project', ['tasks.search_value', 'search', 'marathon']),
        [2],
      );
    });

    test('ranks name matches above description matches', () async {
      await store.replaceScope(_task, 'acme', [
        {'id': 1, 'name': 'Autre', 'description': 'du kafka partout'},
        {'id': 2, 'name': 'Kafka', 'description': 'rien'},
      ]);

      expect(
        await search('task', [
          'search_value',
          'search',
          'kafka',
        ], orderBy: 'search_value:desc'),
        [2, 1],
      );
    });

    test('ignores rank ordering without a search rule', () async {
      expect(
        await search('task', null, orderBy: 'search_value:desc'),
        hasLength(3),
      );
    });

    test('rejects other operators on the fulltext field', () async {
      await expectLater(
        search('task', ['search_value', '=', 'x']),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        search('task', ['name', 'search', 'x']),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('index maintenance', () {
    setUp(seed);

    test('follows upserts, deltas and scope replacement', () async {
      await store.upsertAll(_task, 'acme', [
        {'id': 3, 'name': 'inventaire', 'description': null, 'email': null},
      ]);

      expect(await search('task', ['search_value', 'search', 'projet']), [1]);
      expect(await search('task', ['search_value', 'search', 'inventaire']), [
        3,
      ]);

      await store.applyDelta(_task, 'acme', [], [2]);

      expect(
        await search('task', ['search_value', 'search', 'marathon']),
        isEmpty,
      );

      await store.replaceScope(_task, 'acme', [
        {'id': 5, 'name': 'unique', 'description': null, 'email': null},
      ]);

      expect(
        await search('task', ['search_value', 'search', 'reunion']),
        isEmpty,
      );
      expect(await search('task', ['search_value', 'search', 'unique']), [5]);
    });
  });

  group('self repair', () {
    test('recreates a dropped FTS index and reindexes', () async {
      await seed();
      await db.customStatement('DROP TABLE "task_fts"');

      final migration = await store.ensureModel(_task);

      expect(migration.needsSync, isFalse);
      expect(await search('task', ['search_value', 'search', 'reunion']), [1]);
    });

    test('recreates missing triggers', () async {
      await seed();
      await db.customStatement('DROP TRIGGER "task_fts_au"');
      await store.ensureModel(_task);

      await store.upsertAll(_task, 'acme', [
        {'id': 1, 'name': 'Renommée', 'description': null, 'email': null},
      ]);

      expect(
        await search('task', ['search_value', 'search', 'reunion']),
        isEmpty,
      );
      expect(await search('task', ['search_value', 'search', 'renommée']), [1]);
    });

    test('recomputes locally when the search config changes', () async {
      const nameOnly = LocalModelSchema(
        name: 'task',
        apiName: 'tasks',
        fields: {
          'id': LocalFieldSchema(name: 'id', type: 'integer'),
          'name': LocalFieldSchema(name: 'name', type: 'char'),
          'description': LocalFieldSchema(name: 'description', type: 'text'),
          'email': LocalFieldSchema(name: 'email', type: 'email'),
          'project': LocalFieldSchema(
            name: 'project',
            type: 'many2one',
            target: 'project',
          ),
        },
        searchField: 'search_value',
        searchWeights: {'name': 'a'},
      );

      await store.ensureModel(nameOnly);
      await store.ensureModel(_project);
      await store.replaceScope(nameOnly, 'acme', [
        {'id': 1, 'name': 'Tâche', 'description': 'contenu caché'},
      ]);

      expect(
        await search('task', ['search_value', 'search', 'caché']),
        isEmpty,
      );

      final migration = await store.ensureModel(_task);

      expect(migration.needsSync, isFalse);
      expect(await search('task', ['search_value', 'search', 'caché']), [1]);
    });

    test(
      'builds the search machinery when a model becomes searchable',
      () async {
        const plain = LocalModelSchema(
          name: 'task',
          apiName: 'tasks',
          fields: {
            'id': LocalFieldSchema(name: 'id', type: 'integer'),
            'name': LocalFieldSchema(name: 'name', type: 'char'),
            'description': LocalFieldSchema(name: 'description', type: 'text'),
            'email': LocalFieldSchema(name: 'email', type: 'email'),
            'project': LocalFieldSchema(
              name: 'project',
              type: 'many2one',
              target: 'project',
            ),
          },
        );

        await store.ensureModel(plain);
        await store.ensureModel(_project);
        await store.replaceScope(plain, 'acme', [
          {'id': 1, 'name': 'Réunion', 'description': 'projet alpha'},
        ]);

        const plainSchema = LocalSchema({'task': plain, 'project': _project});

        await expectLater(
          store.query(
            plainSchema,
            'task',
            scope: 'acme',
            filter: ['search_value', 'search', 'alpha'],
          ),
          throwsA(isA<InvalidFilterException>()),
        );

        final migration = await store.ensureModel(_task);

        expect(migration.needsSync, isFalse);
        expect(await search('task', ['search_value', 'search', 'alpha']), [1]);
      },
    );
  });
}
