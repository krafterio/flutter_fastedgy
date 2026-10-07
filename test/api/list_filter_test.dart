/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const filter = ListFilter([
    ['partner', 'icontains', 'edf'],
    ['time', '>=', '2026-01-01T00:00:00.000'],
    ['time', '<', '2026-04-01T00:00:00.000'],
    [
      '|',
      [
        [
          'amount',
          'between',
          [10, 50],
        ],
        [
          'amount',
          'between',
          [-50, -10],
        ],
      ],
    ],
  ]);

  group('fields', () {
    test('hands a column the rules on its field, in their order', () {
      expect(filter.on('time'), [
        ['time', '>=', '2026-01-01T00:00:00.000'],
        ['time', '<', '2026-04-01T00:00:00.000'],
      ]);
      expect(filter.on('label'), isEmpty);
    });

    test('reads a condition as a rule of the field its rules share', () {
      expect(filter.on('amount').single.first, '|');
      expect(filter.fields, {'partner', 'time', 'amount'});
    });

    test('a condition over two fields belongs to none', () {
      expect(
        ListFilter.fieldOf([
          '|',
          [
            ['partner', '=', 'a'],
            ['label', '=', 'b'],
          ],
        ]),
        isNull,
      );
      expect(ListFilter.fieldOf(['|', 'amount']), isNull);
      expect(ListFilter.fieldOf(['expense', 'is empty']), 'expense');
    });

    test('puts new rules in place of the ones on a field', () {
      final next = filter.withField('time', [
        ['time', '>=', '2026-02-01T00:00:00.000'],
      ]);

      expect(next.on('time'), [
        ['time', '>=', '2026-02-01T00:00:00.000'],
      ]);
      expect(next.on('partner'), filter.on('partner'));
    });

    test('an empty replacement stops filtering on the field', () {
      final next = filter.withField('partner', const []);

      expect(next.fields, {'time', 'amount'});
      expect(ListFilter.empty.withField('label', const []).isEmpty, isTrue);
    });
  });

  group('encode / decode', () {
    test('round trips as a JSON array of rules', () {
      expect(filter.encode(), startsWith('[["partner","icontains","edf"]'));
      expect(ListFilter.decode(filter.encode()), filter);
    });

    test('writes nothing when nothing is filtered', () {
      expect(ListFilter.empty.encode(), '');
    });

    test('reads what is not an array of rules as no filter', () {
      expect(ListFilter.decode(null), ListFilter.empty);
      expect(ListFilter.decode(''), ListFilter.empty);
      expect(ListFilter.decode('[["partner"'), ListFilter.empty);
      expect(ListFilter.decode('{"partner":"edf"}'), ListFilter.empty);
      expect(ListFilter.decode('"partner"'), ListFilter.empty);
    });

    test('drops a rule naming no field, or a field allow refuses', () {
      final decoded = ListFilter.decode(
        '[["label","icontains","pain"],["secret","=",1],[],"partner",[3,"=",1]]',
        allow: (field) => field != 'secret',
      );

      expect(
        decoded,
        const ListFilter([
          ['label', 'icontains', 'pain'],
        ]),
      );
    });
  });
}
