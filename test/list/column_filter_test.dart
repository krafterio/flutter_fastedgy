/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'list_support.dart';

void main() {
  group('the rules of a column', () {
    test('are those of its field at the first level of the expression', () {
      final expression = [
        '&',
        [
          ['name', 'icontains', 'lamp'],
          [
            '|',
            [
              [
                'status',
                'in',
                ['open'],
              ],
              ['status', 'is empty'],
            ],
          ],
          ['owner', '=', 3],
        ],
      ];

      expect(columnRules(expression, 'status'), [
        [
          '|',
          [
            [
              'status',
              'in',
              ['open'],
            ],
            ['status', 'is empty'],
          ],
        ],
      ]);
      expect(columnRules(['name', '=', 'a'], 'name'), [
        ['name', '=', 'a'],
      ]);
      expect(columnRules(null, 'name'), isEmpty);
    });

    test('replace those of its field, the others staying, and apply with an expression that is any of its items', () {
      expect(
        withColumnRules(
          [
            ['name', 'icontains', 'lamp'],
            ['owner', '=', 3],
          ],
          'name',
          [
            ['name', 'icontains', 'desk'],
          ],
        ),
        [
          '&',
          [
            ['owner', '=', 3],
            ['name', 'icontains', 'desk'],
          ],
        ],
      );
      expect(withColumnRules(['name', '=', 'a'], 'name', []), isNull);

      final either = [
        '|',
        [
          ['a', '=', 1],
          ['b', '=', 2],
        ],
      ];

      expect(
        withColumnRules(either, 'name', [
          ['name', '=', 'x'],
        ]),
        [
          '&',
          [
            either,
            ['name', '=', 'x'],
          ],
        ],
      );
    });
  });

  group('the filters of the package', () {
    test('read back what they write', () {
      const text = TextColumnFilter('name', 'Name');
      const numbers = NumberRangeColumnFilter('price', 'Price');
      const days = DateRangeColumnFilter('due', 'Due');
      const choices = ChoiceColumnFilter(
        'status',
        'Status',
        options: [
          ColumnFilterOption('open', 'Open'),
          ColumnFilterOption(null, 'Empty'),
        ],
      );

      expect(text.write('  lamp '), [
        ['name', 'icontains', 'lamp'],
      ]);
      expect(text.read(text.write('lamp')), 'lamp');
      expect(text.write(' '), isEmpty);

      expect(numbers.write((min: 10, max: null)), [
        ['price', '>=', 10],
      ]);
      expect(numbers.read(numbers.write((min: 10, max: 20))), (
        min: 10,
        max: 20,
      ));

      expect(days.write((from: '2026-10-01', to: '2026-10-31')), [
        ['due', '>=', '2026-10-01'],
        ['due', '<', '2026-11-01'],
      ]);
      expect(days.read(days.write((from: null, to: '2026-10-31'))), (
        from: null,
        to: '2026-10-31',
      ));

      expect(choices.write({'open', null}), [
        [
          '|',
          [
            [
              'status',
              'in',
              ['open'],
            ],
            ['status', 'is empty'],
          ],
        ],
      ]);
      expect(choices.read(choices.write({'open', null})), {'open', null});
      expect(choices.describe({'open', null}), 'Open, Empty');
      expect(choices.write({}), isEmpty);
    });

    test('compare a datetime with the instants that start the local days', () {
      const days = DateRangeColumnFilter(
        'created_at',
        'Created',
        datetime: true,
      );
      final rules = days.write((from: '2026-10-01', to: '2026-10-31'));

      expect(rules, [
        ['created_at', '>=', dayStart('2026-10-01')],
        ['created_at', '<', dayStart('2026-11-01')],
      ]);
      expect(days.read(rules), (from: '2026-10-01', to: '2026-10-31'));
    });

    test('set and read their value in the expression of a list', () {
      const text = TextColumnFilter('name', 'Name');
      final expression = text.applyTo(['owner', '=', 3], 'lamp');

      expect(expression, [
        '&',
        [
          ['owner', '=', 3],
          ['name', 'icontains', 'lamp'],
        ],
      ]);
      expect(text.valueIn(expression), 'lamp');
      expect(text.applyTo(expression, null), ['owner', '=', 3]);
    });

    test('are chosen by the kind of the field', () {
      expect(
        columnFilterOf(metaField('name', type: 'char')),
        isA<TextColumnFilter>(),
      );
      expect(
        columnFilterOf(metaField('price', type: 'decimal')),
        isA<NumberRangeColumnFilter>(),
      );
      expect(
        (columnFilterOf(
          metaField('at', type: 'datetime'),
        ) as DateRangeColumnFilter).datetime,
        isTrue,
      );
      expect(
        (columnFilterOf(
          metaField('status', type: 'choice', choices: {'open': 'Open'}),
        ) as ChoiceColumnFilter).options.map((option) => option.value),
        ['open', null],
      );
      expect(
        (columnFilterOf(
          metaField(
            'status',
            type: 'choice',
            required: true,
            choices: {'open': 'Open'},
          ),
        ) as ChoiceColumnFilter).options.map((option) => option.value),
        ['open'],
      );
      expect(columnFilterOf(metaField('owner', type: 'many2one')), isNull);
    });
  });

  group('the filter of a relation', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late ThingServer server;

    setUp(() async {
      await setUpList();
      server = ThingServer()
        ..answer = (request) {
          final id = int.tryParse(request.path.split('/').last);

          return id == null || id > 100
              ? null
              : MockResponse.json({'id': id, 'name': 'Thing $id'});
        };
    });

    test('reads the records chosen, and names them once resolved', () async {
      final filter = RelationColumnFilter(
        'owner',
        'Owner',
        source: ValueSource(
          reader: ThingApi(server.fetcher),
          fields: const ['name'],
          label: (record) => '${record['name']}',
        ),
      );
      final rules = filter.write({3, null});

      expect(rules, [
        [
          '|',
          [
            [
              'owner',
              'in',
              [3],
            ],
            ['owner', 'is empty'],
          ],
        ],
      ]);
      expect(filter.read(rules), {3, null});
      expect(filter.describe({3, 4}), '#3, #4');

      filter.remember(4, 'Four');
      await filter.resolveLabels({3, 4, null});

      expect(filter.describe({3, 4, null}), 'Thing 3, Four, Empty');
      expect(server.requests.single.headers['X-Fields'], 'id,name');
    });

    test('is chosen for a relation whose model the context reads', () {
      final filter = columnFilterOf(
        metaField('owner', type: 'many2one', target: 'thing'),
        context: const ValueSourceContext(prefix: '/acme'),
      );

      expect(filter, isA<RelationColumnFilter>());
      expect(
        ((filter! as RelationColumnFilter).source.reader! as GenericApiModel)
            .basePath,
        '/acme',
      );
    });
  });
}
