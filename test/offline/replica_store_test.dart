/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

LocalModelSchema _userSchema({
  bool withPhone = false,
  String nameType = 'char',
}) {
  return LocalModelSchema(
    name: 'user',
    apiName: 'users',
    fields: {
      'id': const LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: nameType),
      'active': const LocalFieldSchema(name: 'active', type: 'boolean'),
      'workspace': const LocalFieldSchema(
        name: 'workspace',
        type: 'many2one',
        target: 'workspace',
      ),
      'memberships': const LocalFieldSchema(
        name: 'memberships',
        type: 'one2many',
        target: 'workspace_user',
      ),
      if (withPhone)
        'phone': const LocalFieldSchema(name: 'phone', type: 'char'),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReplicaStore store;

  setUp(() async {
    store = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
  });

  tearDown(() => store.close());

  group('LocalModelSchema', () {
    test('columns exclude inverse relations', () {
      final schema = _userSchema();

      expect(schema.columns.map((c) => c.name), isNot(contains('memberships')));
      expect(schema.columns.map((c) => c.name), contains('workspace'));
    });

    test('fingerprint changes with the column set', () {
      expect(_userSchema().fingerprint, _userSchema().fingerprint);
      expect(
        _userSchema().fingerprint,
        isNot(_userSchema(withPhone: true).fingerprint),
      );
      expect(
        _userSchema().fingerprint,
        isNot(_userSchema(nameType: 'text').fingerprint),
      );
    });
  });

  group('LocalSchema.resolveReverseField', () {
    test('resolves an unambiguous reverse FK and rejects ambiguity', () {
      const flowUnambiguous = LocalSchema({
        'user': LocalModelSchema(
          name: 'user',
          apiName: 'users',
          fields: {
            'id': LocalFieldSchema(name: 'id', type: 'integer'),
            'flows': LocalFieldSchema(
              name: 'flows',
              type: 'one2many',
              target: 'flow',
            ),
          },
        ),
        'flow': LocalModelSchema(
          name: 'flow',
          apiName: 'flows',
          fields: {
            'id': LocalFieldSchema(name: 'id', type: 'integer'),
            'owner': LocalFieldSchema(
              name: 'owner',
              type: 'many2one',
              target: 'user',
            ),
          },
        ),
      });

      expect(flowUnambiguous.resolveReverseField('user', 'flows'), 'owner');

      const flowAmbiguous = LocalSchema({
        'user': LocalModelSchema(
          name: 'user',
          apiName: 'users',
          fields: {
            'id': LocalFieldSchema(name: 'id', type: 'integer'),
            'flows': LocalFieldSchema(
              name: 'flows',
              type: 'one2many',
              target: 'flow',
            ),
          },
        ),
        'flow': LocalModelSchema(
          name: 'flow',
          apiName: 'flows',
          fields: {
            'id': LocalFieldSchema(name: 'id', type: 'integer'),
            'owner': LocalFieldSchema(
              name: 'owner',
              type: 'many2one',
              target: 'user',
            ),
            'assignee': LocalFieldSchema(
              name: 'assignee',
              type: 'many2one',
              target: 'user',
            ),
          },
        ),
      });

      expect(flowAmbiguous.resolveReverseField('user', 'flows'), isNull);
    });
  });

  group('ReplicaStore', () {
    test('creates the table and round-trips scoped records', () async {
      final migration = await store.ensureModel(_userSchema());

      expect(migration.created, isTrue);
      expect(migration.needsSync, isTrue);

      await store.upsertAll(_userSchema(), 'acme', [
        {
          'id': 1,
          'name': 'Ada',
          'active': true,
          'workspace': {'id': 7},
          'extra': 'kept',
        },
      ]);
      await store.upsertAll(_userSchema(), 'globex', [
        {'id': 1, 'name': 'Ada @globex'},
      ]);

      final acme = await store.getAll('user', 'acme');

      expect(acme, hasLength(1));
      expect(acme.single['name'], 'Ada');
      expect(acme.single['extra'], 'kept'); // full payload fidelity
      expect(
        (await store.getAll('user', 'globex')).single['name'],
        'Ada @globex',
      );
      expect((await store.getById('user', 'acme', 1))?['workspace'], {'id': 7});
    });

    test('replaceScope prunes only its scope', () async {
      await store.ensureModel(_userSchema());
      await store.upsertAll(_userSchema(), 'acme', [
        {'id': 1, 'name': 'Ada'},
        {'id': 2, 'name': 'Grace'},
      ]);
      await store.upsertAll(_userSchema(), 'globex', [
        {'id': 3, 'name': 'Edsger'},
      ]);

      await store.replaceScope(_userSchema(), 'acme', [
        {'id': 2, 'name': 'Grace'},
      ]);

      expect(await store.getAll('user', 'acme'), hasLength(1));
      expect(await store.getAll('user', 'globex'), hasLength(1));
    });

    test('same fingerprint is a no-op migration', () async {
      await store.ensureModel(_userSchema());
      final migration = await store.ensureModel(_userSchema());

      expect(migration.created, isFalse);
      expect(migration.rebuilt, isFalse);
    });

    test('additive change alters the table and keeps the data', () async {
      await store.ensureModel(_userSchema());
      await store.upsertAll(_userSchema(), 'acme', [
        {'id': 1, 'name': 'Ada'},
      ]);

      final migration = await store.ensureModel(_userSchema(withPhone: true));

      expect(migration.rebuilt, isFalse);
      expect(migration.needsSync, isFalse);
      expect(await store.getAll('user', 'acme'), hasLength(1));

      await store.upsertAll(_userSchema(withPhone: true), 'acme', [
        {'id': 2, 'name': 'Grace', 'phone': '+33'},
      ]);

      expect(await store.getAll('user', 'acme'), hasLength(2));
    });

    test(
      'incompatible change rebuilds the table and requires a resync',
      () async {
        await store.ensureModel(_userSchema());
        await store.upsertAll(_userSchema(), 'acme', [
          {'id': 1, 'name': 'Ada'},
        ]);

        final migration = await store.ensureModel(
          _userSchema(nameType: 'integer'),
        );

        expect(migration.rebuilt, isTrue);
        expect(migration.needsSync, isTrue);
        expect(await store.getAll('user', 'acme'), isEmpty);
      },
    );

    test('clearAll drops every replicated model', () async {
      await store.ensureModel(_userSchema());
      await store.upsertAll(_userSchema(), 'acme', [
        {'id': 1, 'name': 'Ada'},
      ]);

      await store.clearAll();

      final migration = await store.ensureModel(_userSchema());
      expect(migration.created, isTrue);
      expect(await store.getAll('user', 'acme'), isEmpty);
    });

    test('a reset replica recreates the tables after a logout purge', () async {
      final replica = Replica.withSchema(
        store,
        LocalSchema({'user': _userSchema()}),
      );

      expect(await replica.ensure('user'), isTrue);
      await store.upsertAll(_userSchema(), 'acme', [
        {'id': 1, 'name': 'Ada'},
      ]);

      // Logout: drops the tables and forgets the ensured models together -
      // a partial purge leaves ensure() answering for dropped tables.
      await replica.clearAll();

      expect(await replica.ensure('user'), isTrue);
      await store.upsertAll(_userSchema(), 'acme', [
        {'id': 2, 'name': 'Grace'},
      ]);
      expect(await store.getAll('user', 'acme'), hasLength(1));
    });
  });

  group('ReplicaStore self-repair', () {
    late OfflineDatabase db;
    late ReplicaStore repairStore;

    LocalModelSchema projectSchema() => const LocalModelSchema(
      name: 'project',
      apiName: 'projects',
      fields: {
        'id': LocalFieldSchema(name: 'id', type: 'integer'),
        'name': LocalFieldSchema(name: 'name', type: 'char'),
        'tags': LocalFieldSchema(
          name: 'tags',
          type: 'many2many',
          target: 'tag',
        ),
      },
    );

    setUp(() async {
      db = OfflineDatabase(NativeDatabase.memory());
      repairStore = ReplicaStore(databaseOpener: () => db);
      await repairStore.open();
    });

    tearDown(() => repairStore.close());

    test('repairs an older system-column layout even when the fingerprint '
        'matches', () async {
      final schema = _userSchema();
      // A database written by an older storage layout: ws_scope/data system
      // columns, and a stored fingerprint that matches anyway (it only
      // covers the model's fields).
      await db.customStatement(
        'CREATE TABLE "user" (ws_scope CHAR, data JSON, "id" INTEGER, '
        '"name" TEXT, "active" INTEGER, "workspace" INTEGER, '
        'PRIMARY KEY (ws_scope, id))',
      );
      await db.customStatement(
        'INSERT INTO _replica_models (model, fingerprint) VALUES (?, ?)',
        ['user', schema.fingerprint],
      );

      final migration = await repairStore.ensureModel(schema);

      expect(migration.rebuilt, isTrue);
      expect(migration.needsSync, isTrue);

      await repairStore.upsertAll(schema, 'acme', [
        {'id': 1, 'name': 'Ada', 'active': true},
      ]);
      expect(await repairStore.getAll('user', 'acme'), hasLength(1));
    });

    test('bridges old r_-prefixed tables and repairs their layout', () async {
      final schema = _userSchema();
      await db.customStatement(
        'CREATE TABLE "r_user" (ws_scope CHAR, data JSON, "id" INTEGER, '
        '"name" TEXT, "active" INTEGER, "workspace" INTEGER, '
        'PRIMARY KEY (ws_scope, id))',
      );
      await db.customStatement(
        'INSERT INTO _replica_models (model, fingerprint) VALUES (?, ?)',
        ['user', schema.fingerprint],
      );

      final migration = await repairStore.ensureModel(schema);

      expect(migration.rebuilt, isTrue);

      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table' "
                    "AND name IN ('user', 'r_user')",
                  )
                  .get())
              .map((row) => row.read<String>('name'))
              .toList();
      expect(tables, ['user']);
    });

    test('repairs pivot tables from an older layout', () async {
      final schema = projectSchema();
      await db.customStatement(
        'CREATE TABLE "project__tags" (ws_scope CHAR, parent_id INTEGER, '
        'target_id INTEGER, PRIMARY KEY (ws_scope, parent_id, target_id))',
      );

      await repairStore.ensureModel(schema);

      final columns =
          (await db.customSelect('PRAGMA table_info("project__tags")').get())
              .map((row) => row.read<String>('name'))
              .toList();
      expect(columns, ['_workspace', 'parent_id', 'target_id']);

      await repairStore.upsertAll(schema, 'acme', [
        {
          'id': 1,
          'name': 'Blum',
          'tags': [
            {'id': 5},
          ],
        },
      ]);
      expect(
        (await repairStore.getById('project', 'acme', 1))?['name'],
        'Blum',
      );
    });
  });
}
