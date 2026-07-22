/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

const _schema = LocalSchema({
  'user': LocalModelSchema(
    name: 'user',
    apiName: 'users',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'email': LocalFieldSchema(name: 'email', type: 'email'),
      'active': LocalFieldSchema(name: 'active', type: 'boolean'),
      'age': LocalFieldSchema(name: 'age', type: 'integer'),
    },
  ),
  'workspace': LocalModelSchema(
    name: 'workspace',
    apiName: 'workspaces',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'owner': LocalFieldSchema(
        name: 'owner',
        type: 'many2one',
        target: 'user',
      ),
      'members': LocalFieldSchema(
        name: 'members',
        type: 'one2many',
        target: 'workspace_user',
      ),
    },
  ),
  'workspace_user': LocalModelSchema(
    name: 'workspace_user',
    apiName: 'workspace_users',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'role': LocalFieldSchema(name: 'role', type: 'choice'),
      'workspace': LocalFieldSchema(
        name: 'workspace',
        type: 'many2one',
        target: 'workspace',
      ),
      'user': LocalFieldSchema(name: 'user', type: 'many2one', target: 'user'),
    },
  ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReplicaStore store;

  Future<({List<Map<String, dynamic>> records, int total})> query(
    String model, {
    dynamic filter,
    dynamic orderBy,
    int? limit,
    int? offset,
  }) {
    return store.query(
      _schema,
      model,
      scope: 'acme',
      filter: filter,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  List<Object?> names(List<Map<String, dynamic>> records) =>
      records.map((r) => r['name']).toList();

  setUp(() async {
    store = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();

    for (final model in _schema.models.values) {
      await store.ensureModel(model);
    }

    await store.replaceScope(_schema.models['user']!, 'acme', [
      {'id': 1, 'name': 'Ada', 'email': 'ada@x.io', 'active': true, 'age': 30},
      {
        'id': 2,
        'name': 'Grace',
        'email': 'grace@x.io',
        'active': false,
        'age': 40,
      },
      {'id': 3, 'name': 'marc', 'email': null, 'active': true, 'age': 25},
    ]);
    await store.replaceScope(_schema.models['user']!, 'globex', [
      {'id': 9, 'name': 'Intrus', 'active': true, 'age': 99},
    ]);
    await store.replaceScope(_schema.models['workspace']!, 'acme', [
      {
        'id': 1,
        'name': 'Krafter',
        'owner': {'id': 1},
      },
      {'id': 2, 'name': 'Beta', 'owner': null},
    ]);
    await store.replaceScope(_schema.models['workspace_user']!, 'acme', [
      {
        'id': 1,
        'role': 'ADMIN',
        'workspace': {'id': 1},
        'user': {'id': 1},
      },
      {
        'id': 2,
        'role': 'MEMBER',
        'workspace': {'id': 1},
        'user': {'id': 2},
      },
      {
        'id': 3,
        'role': 'ADMIN',
        'workspace': {'id': 2},
        'user': {'id': 2},
      },
    ]);
  });

  tearDown(() => store.close());

  group('operators', () {
    test('equality and inequality', () async {
      expect(
        names((await query('user', filter: ['name', '=', 'Ada'])).records),
        ['Ada'],
      );
      expect((await query('user', filter: ['name', '!=', 'Ada'])).total, 2);
    });

    test('like is case sensitive, ilike is not', () async {
      expect((await query('user', filter: ['name', 'like', 'GR%'])).total, 0);
      expect(
        names((await query('user', filter: ['name', 'ilike', 'GR%'])).records),
        ['Grace'],
      );
    });

    test('contains is case sensitive, icontains is not', () async {
      expect(
        (await query('user', filter: ['name', 'contains', 'ADA'])).total,
        0,
      );
      expect(
        names(
          (await query('user', filter: ['name', 'icontains', 'ADA'])).records,
        ),
        ['Ada'],
      );
    });

    test('starts with / ends with', () async {
      expect(
        names(
          (await query('user', filter: ['name', 'starts with', 'Gr'])).records,
        ),
        ['Grace'],
      );
      expect(
        names(
          (await query('user', filter: ['name', 'ends with', 'rc'])).records,
        ),
        ['marc'],
      );
    });

    test('in, not in, between', () async {
      expect(
        (await query(
          'user',
          filter: [
            'age',
            'in',
            [30, 40],
          ],
        )).total,
        2,
      );
      expect(
        names(
          (await query(
            'user',
            filter: [
              'age',
              'not in',
              [30, 40],
            ],
          )).records,
        ),
        ['marc'],
      );
      expect(
        (await query(
          'user',
          filter: [
            'age',
            'between',
            [26, 45],
          ],
        )).total,
        2,
      );
      expect((await query('user', filter: ['age', 'in', <int>[]])).total, 0);
    });

    test('booleans and emptiness', () async {
      expect((await query('user', filter: ['active', 'is true'])).total, 2);
      expect(
        names((await query('user', filter: ['active', 'is false'])).records),
        ['Grace'],
      );
      expect(
        names((await query('user', filter: ['email', 'is empty'])).records),
        ['marc'],
      );
      expect((await query('user', filter: ['email', 'is not empty'])).total, 2);
    });

    test('m2o leaf compares ids (bare or wrapped)', () async {
      expect(
        names((await query('workspace', filter: ['owner', '=', 1])).records),
        ['Krafter'],
      );
      expect(
        (await query('workspace', filter: ['owner', 'is empty'])).total,
        1,
      );
    });
  });

  group('nested paths', () {
    test('m2o path', () async {
      expect(
        names(
          (await query(
            'workspace',
            filter: ['owner.name', '=', 'Ada'],
          )).records,
        ),
        ['Krafter'],
      );
    });

    test('o2m path (EXISTS)', () async {
      expect(
        (await query(
          'workspace',
          filter: ['members.role', '=', 'ADMIN'],
        )).total,
        2,
      );
      expect(
        (await query(
          'workspace',
          filter: ['members.user.name', '=', 'Grace'],
        )).total,
        2,
      );
    });

    test(
      'AND rules on the same to-many path hit the same related row',
      () async {
        // ws1 has ADMIN=Ada and MEMBER=Grace: independent EXISTS would match it,
        // the server's joined-lookup semantics must not.
        final result = await query(
          'workspace',
          filter: [
            ['members.role', '=', 'ADMIN'],
            ['members.user.name', '=', 'Grace'],
          ],
        );

        expect(names(result.records), ['Beta']);
      },
    );

    test('OR branches get independent EXISTS', () async {
      final result = await query(
        'workspace',
        filter: [
          '|',
          [
            ['members.user.name', '=', 'Ada'],
            ['name', '=', 'Beta'],
          ],
        ],
      );

      expect(result.total, 2);
    });

    test('nested OR inside AND', () async {
      final result = await query(
        'user',
        filter: [
          ['active', 'is true'],
          [
            '|',
            [
              ['age', '<', 26],
              ['name', '=', 'Ada'],
            ],
          ],
        ],
      );

      expect(result.total, 2);
    });
  });

  group('order by and pagination', () {
    test('nested m2o order with PostgreSQL null placement', () async {
      final asc = await query('workspace', orderBy: 'owner.name');
      expect(names(asc.records), ['Krafter', 'Beta']); // NULLS LAST

      final desc = await query('workspace', orderBy: 'owner.name:desc');
      expect(names(desc.records), ['Beta', 'Krafter']); // NULLS FIRST
    });

    test('limit/offset with honest total', () async {
      final result = await query('user', orderBy: 'name', limit: 2, offset: 1);

      expect(result.total, 3);
      expect(names(result.records), ['Grace', 'marc']);
    });
  });

  group('scoping and unsupported', () {
    test('records outside the scope are invisible', () async {
      expect((await query('user')).total, 3);
      expect((await query('user', filter: ['name', '=', 'Intrus'])).total, 0);
    });

    test('to-many leaf and unknown operator are rejected', () async {
      await expectLater(
        query(
          'workspace',
          filter: [
            'members',
            'in',
            [1],
          ],
        ),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        query('user', filter: ['name', 'match', 'ada']),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('unknown field raises an invalid filter', () async {
      await expectLater(
        query('user', filter: ['nope', '=', 1]),
        throwsA(isA<InvalidFilterException>()),
      );
    });
  });
}
