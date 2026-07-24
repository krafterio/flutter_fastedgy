/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

const _schema = LocalSchema({
  'document': LocalModelSchema(
    name: 'document',
    apiName: 'documents',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'embedding': LocalFieldSchema(name: 'embedding', type: 'vector'),
    },
  ),
  'note': LocalModelSchema(
    name: 'note',
    apiName: 'notes',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'label': LocalFieldSchema(name: 'label', type: 'char'),
      'document': LocalFieldSchema(
        name: 'document',
        type: 'many2one',
        target: 'document',
      ),
    },
  ),
});

// Query vector (unit). Distances to it:
//   Alpha [1, 0, 0]     l1 0    l2 0      cosine 0    inner product -1
//   Beta  [0, 1, 0]     l1 2    l2 1.414  cosine 1    inner product 0
//   Gamma [0.6, 0.8, 0] l1 1.2  l2 0.894  cosine 0.4  inner product -0.6
const _query = [1.0, 0.0, 0.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReplicaStore store;

  Future<({List<Map<String, dynamic>> records, int total})> query(
    String model, {
    dynamic filter,
    dynamic orderBy = 'name',
  }) {
    return store.query(
      _schema,
      model,
      scope: 'acme',
      filter: filter,
      orderBy: orderBy,
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

    await store.replaceScope(_schema.models['document']!, 'acme', [
      {
        'id': 1,
        'name': 'Alpha',
        'embedding': [1.0, 0.0, 0.0],
      },
      {
        'id': 2,
        'name': 'Beta',
        'embedding': [0.0, 1.0, 0.0],
      },
      {
        'id': 3,
        'name': 'Gamma',
        'embedding': [0.6, 0.8, 0.0],
      },
      {'id': 4, 'name': 'Nowhere', 'embedding': null},
      // Wrong arity: pgvector raises, the join would score the common prefix.
      {
        'id': 5,
        'name': 'Truncated',
        'embedding': [1.0, 0.0],
      },
      // Zero norm: cosine divides by zero.
      {
        'id': 6,
        'name': 'Origin',
        'embedding': [0.0, 0.0, 0.0],
      },
    ]);
    await store.replaceScope(_schema.models['document']!, 'globex', [
      {
        'id': 9,
        'name': 'Intrus',
        'embedding': [1.0, 0.0, 0.0],
      },
    ]);
    await store.replaceScope(_schema.models['note']!, 'acme', [
      {
        'id': 1,
        'label': 'first',
        'document': {'id': 1},
      },
      {
        'id': 2,
        'label': 'second',
        'document': {'id': 2},
      },
      {'id': 3, 'label': 'draft', 'document': null},
    ]);
  });

  tearDown(() => store.close());

  group('distance metrics', () {
    test('cosine distance', () async {
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'cosine distance <',
              [_query, 0.5],
            ],
          )).records,
        ),
        ['Alpha', 'Gamma'],
      );
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'cosine distance <',
              [_query, 0.4],
            ],
          )).records,
        ),
        ['Alpha'],
      );
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'cosine distance <=',
              [_query, 0.4],
            ],
          )).records,
        ),
        ['Alpha', 'Gamma'],
      );
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'cosine distance >=',
              [_query, 1.0],
            ],
          )).records,
        ),
        ['Beta'],
      );
    });

    test('l2 distance is euclidean', () async {
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'l2 distance <',
              [_query, 1.0],
            ],
          )).records,
        ),
        ['Alpha', 'Gamma'],
      );
      // Origin sits at exactly 1.0 from the query vector.
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'l2 distance >',
              [_query, 1.0],
            ],
          )).records,
        ),
        ['Beta'],
      );
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'l2 distance >=',
              [_query, 1.0],
            ],
          )).records,
        ),
        ['Beta', 'Origin'],
      );
    });

    test('l1 distance is manhattan', () async {
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'l1 distance <',
              [_query, 1.5],
            ],
          )).records,
        ),
        ['Alpha', 'Gamma', 'Origin'],
      );
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'l1 distance >=',
              [_query, 2.0],
            ],
          )).records,
        ),
        ['Beta'],
      );
    });

    test('inner product keeps the pgvector negation of <#>', () async {
      // The raw dot products are 1, 0 and 0.6: a positive convention would
      // match nothing here.
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'inner product <',
              [_query, -0.5],
            ],
          )).records,
        ),
        ['Alpha', 'Gamma'],
      );
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'inner product >=',
              [_query, 0.0],
            ],
          )).records,
        ),
        ['Beta', 'Origin'],
      );
    });
  });

  group('non-matching rows', () {
    test('a NULL vector never matches a distance operator', () async {
      final all = await query(
        'document',
        filter: [
          'embedding',
          'l2 distance <',
          [_query, 1000000.0],
        ],
      );

      expect(names(all.records), isNot(contains('Nowhere')));
    });

    test('a dimension mismatch never matches', () async {
      // Truncated is [1, 0]: scoring the common prefix would make it an exact
      // match of the query vector on every metric.
      for (final operator in [
        'cosine distance <',
        'l1 distance <',
        'l2 distance <',
      ]) {
        expect(
          names(
            (await query(
              'document',
              filter: [
                'embedding',
                operator,
                [_query, 0.001],
              ],
            )).records,
          ),
          ['Alpha'],
          reason: operator,
        );
      }
    });

    test('a zero-norm vector never matches under cosine', () async {
      // pgvector yields NaN there, SQLite NULL: neither satisfies `<`.
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'cosine distance <',
              [_query, 1000000.0],
            ],
          )).records,
        ),
        ['Alpha', 'Beta', 'Gamma'],
      );
    });
  });

  group('value forms', () {
    test('both argument orders are accepted', () async {
      final operand = await query(
        'document',
        filter: [
          'embedding',
          'cosine distance <',
          [_query, 0.5],
        ],
      );
      final threshold = await query(
        'document',
        filter: [
          'embedding',
          'cosine distance <',
          [0.5, _query],
        ],
      );

      expect(names(operand.records), ['Alpha', 'Gamma']);
      expect(names(threshold.records), names(operand.records));
    });

    test('integer coordinates are accepted', () async {
      expect(
        names(
          (await query(
            'document',
            filter: [
              'embedding',
              'cosine distance <',
              [
                [1, 0, 0],
                0.5,
              ],
            ],
          )).records,
        ),
        ['Alpha', 'Gamma'],
      );
    });
  });

  group('relations and scoping', () {
    test('vector filter through a m2o chain', () async {
      expect(
        (await query(
          'note',
          orderBy: 'label',
          filter: [
            'document.embedding',
            'cosine distance <',
            [_query, 0.5],
          ],
        )).records.map((r) => r['label']),
        ['first'],
      );
    });

    test('a broken chain never matches', () async {
      expect(
        (await query(
          'note',
          orderBy: 'label',
          filter: [
            'document.embedding',
            'l2 distance <',
            [_query, 1000000.0],
          ],
        )).records.map((r) => r['label']),
        ['first', 'second'],
      );
    });

    test('other workspaces stay invisible', () async {
      expect(
        (await query(
          'document',
          filter: [
            'embedding',
            'cosine distance <',
            [_query, 0.001],
          ],
        )).total,
        1,
      );
    });
  });

  group('rejections', () {
    test('bare distance operators are not boolean predicates', () async {
      for (final operator in [
        'l1 distance',
        'l2 distance',
        'cosine distance',
        'inner product',
      ]) {
        await expectLater(
          query('document', filter: ['embedding', operator, _query]),
          throwsA(isA<UnsupportedError>()),
          reason: operator,
        );
      }
    });

    test('the server exposes no other operator on a vector field', () async {
      for (final filter in [
        ['embedding', '=', _query],
        ['embedding', 'is empty'],
        ['embedding', 'is not empty'],
        ['embedding', 'in', _query],
      ]) {
        await expectLater(
          query('document', filter: filter),
          throwsA(isA<UnsupportedError>()),
          reason: '${filter[1]}',
        );
      }
    });

    test('vector operators are rejected on a non-vector field', () async {
      await expectLater(
        query(
          'document',
          filter: [
            'name',
            'cosine distance <',
            [_query, 0.5],
          ],
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('order_by on a vector field is rejected', () async {
      await expectLater(
        query('document', orderBy: 'embedding'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('malformed values raise an invalid filter error', () async {
      for (final value in [
        _query,
        [_query],
        [0.5, 0.5],
        [
          [_query, _query],
          0.5,
        ],
        [<double>[], 0.5],
        [
          ['a', 'b', 'c'],
          0.5,
        ],
      ]) {
        await expectLater(
          query('document', filter: ['embedding', 'cosine distance <', value]),
          throwsA(isA<InvalidFilterException>()),
          reason: '$value',
        );
      }
    });
  });
}
