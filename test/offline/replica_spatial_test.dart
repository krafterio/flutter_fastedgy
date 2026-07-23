/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

const _schema = LocalSchema({
  'store': LocalModelSchema(
    name: 'store',
    apiName: 'stores',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'location': LocalFieldSchema(name: 'location', type: 'point'),
    },
  ),
  'visit': LocalModelSchema(
    name: 'visit',
    apiName: 'visits',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'label': LocalFieldSchema(name: 'label', type: 'char'),
      'store': LocalFieldSchema(
        name: 'store',
        type: 'many2one',
        target: 'store',
      ),
    },
  ),
});

// Reference point: Paris center. Haversine distances from it:
// Eiffel ≈ 4.2 km, Versailles ≈ 17.9 km, Lyon ≈ 391.5 km.
const _paris = [2.3522, 48.8566];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReplicaStore store;

  Future<({List<Map<String, dynamic>> records, int total})> query(
    String model, {
    dynamic filter,
    dynamic orderBy,
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

    await store.replaceScope(_schema.models['store']!, 'acme', [
      {
        'id': 1,
        'name': 'Eiffel',
        'location': [2.2945, 48.8584],
      },
      {
        'id': 2,
        'name': 'Versailles',
        'location': [2.1204, 48.8049],
      },
      {
        'id': 3,
        'name': 'Lyon',
        'location': [4.8357, 45.7640],
      },
      {'id': 4, 'name': 'Nowhere', 'location': null},
    ]);
    await store.replaceScope(_schema.models['store']!, 'globex', [
      {
        'id': 9,
        'name': 'Intrus',
        'location': [2.2945, 48.8584],
      },
    ]);
    await store.replaceScope(_schema.models['visit']!, 'acme', [
      {
        'id': 1,
        'label': 'morning',
        'store': {'id': 1},
      },
      {
        'id': 2,
        'label': 'noon',
        'store': {'id': 3},
      },
      {'id': 3, 'label': 'draft', 'store': null},
    ]);
  });

  tearDown(() => store.close());

  group('distance operators', () {
    test('spatial within distance keeps the radius, in meters', () async {
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial within distance',
              [_paris, 5000],
            ],
          )).records,
        ),
        ['Eiffel'],
      );
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial within distance',
              [_paris, 20000],
            ],
          )).records,
        ),
        ['Eiffel', 'Versailles'],
      );
    });

    test('the bounding-box prefilter never chops the exact radius', () async {
      // Eiffel is ≈ 4226 m away: a 4300 m radius must keep it even though it
      // sits close to the box edge, a 4200 m radius must drop it.
      expect(
        (await query(
          'store',
          filter: [
            'location',
            'spatial within distance',
            [_paris, 4300],
          ],
        )).total,
        1,
      );
      expect(
        (await query(
          'store',
          filter: [
            'location',
            'spatial within distance',
            [_paris, 4200],
          ],
        )).total,
        0,
      );
    });

    test('spatial distance comparisons', () async {
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial distance <',
              [_paris, 400000],
            ],
          )).records,
        ),
        ['Eiffel', 'Versailles', 'Lyon'],
      );
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial distance <=',
              [_paris, 300000],
            ],
          )).records,
        ),
        ['Eiffel', 'Versailles'],
      );
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial distance >',
              [_paris, 380000],
            ],
          )).records,
        ),
        ['Lyon'],
      );
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial distance >=',
              [_paris, 10000],
            ],
          )).records,
        ),
        ['Versailles', 'Lyon'],
      );
    });

    test('a NULL point never matches a distance operator', () async {
      final huge = await query(
        'store',
        filter: [
          'location',
          'spatial distance <',
          [_paris, 100000000],
        ],
      );

      expect(names(huge.records), isNot(contains('Nowhere')));
    });
  });

  group('geometry predicates (point-vs-point)', () {
    test(
      'equals, contains, within and intersects are point equality',
      () async {
        for (final operator in [
          'spatial equals',
          'spatial contains',
          'spatial within',
          'spatial intersects',
        ]) {
          expect(
            names(
              (await query(
                'store',
                filter: [
                  'location',
                  operator,
                  [2.2945, 48.8584],
                ],
              )).records,
            ),
            ['Eiffel'],
            reason: operator,
          );
        }
      },
    );

    test('disjoint is the negation, NULL points never match', () async {
      expect(
        names(
          (await query(
            'store',
            filter: [
              'location',
              'spatial disjoint',
              [2.2945, 48.8584],
            ],
          )).records,
        ),
        ['Versailles', 'Lyon'],
      );
    });

    test('touches, crosses and overlaps never match two points', () async {
      for (final operator in [
        'spatial touches',
        'spatial crosses',
        'spatial overlaps',
      ]) {
        expect(
          (await query(
            'store',
            filter: [
              'location',
              operator,
              [2.2945, 48.8584],
            ],
          )).total,
          0,
          reason: operator,
        );
      }
    });

    test('is empty / is not empty', () async {
      expect(
        names((await query('store', filter: ['location', 'is empty'])).records),
        ['Nowhere'],
      );
      expect(
        (await query('store', filter: ['location', 'is not empty'])).total,
        3,
      );
    });
  });

  group('relations and scoping', () {
    test('spatial filter through a m2o chain', () async {
      expect(
        (await query(
          'visit',
          filter: [
            'store.location',
            'spatial within distance',
            [_paris, 5000],
          ],
        )).records.map((r) => r['label']),
        ['morning'],
      );
    });

    test(
      'is empty through a broken chain matches (LEFT JOIN parity)',
      () async {
        expect(
          (await query(
            'visit',
            filter: ['store.location', 'is empty'],
          )).records.map((r) => r['label']),
          ['draft'],
        );
      },
    );

    test('other workspaces stay invisible', () async {
      expect(
        (await query(
          'store',
          filter: [
            'location',
            'spatial equals',
            [2.2945, 48.8584],
          ],
        )).total,
        1,
      );
    });
  });

  group('rejections', () {
    test('bare spatial distance is not a boolean predicate', () async {
      await expectLater(
        query('store', filter: ['location', 'spatial distance', _paris]),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('non-spatial operators are rejected on a point field', () async {
      await expectLater(
        query('store', filter: ['location', '=', _paris]),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('spatial operators are rejected on a non-point field', () async {
      await expectLater(
        query('store', filter: ['name', 'spatial equals', _paris]),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('order_by on a point field is rejected', () async {
      await expectLater(
        query('store', orderBy: 'location'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('malformed values raise an invalid filter error', () async {
      await expectLater(
        query(
          'store',
          filter: [
            'location',
            'spatial equals',
            [2.29],
          ],
        ),
        throwsA(isA<InvalidFilterException>()),
      );
      await expectLater(
        query(
          'store',
          filter: [
            'location',
            'spatial within distance',
            [2.29, 48.85],
          ],
        ),
        throwsA(isA<InvalidFilterException>()),
      );
    });
  });
}
