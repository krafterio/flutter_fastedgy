/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  group('plain click', () {
    test('an unsorted field starts ascending', () {
      expect(ListSort.empty.cycle('name'), const ListSort([SortKey('name')]));
    });

    test('cycles ascending → descending → unsorted', () {
      var sort = ListSort.empty.cycle('name');
      expect(sort.keyFor('name')!.ascending, isTrue);

      sort = sort.cycle('name');
      expect(sort.keyFor('name')!.ascending, isFalse);

      sort = sort.cycle('name');
      expect(sort.isEmpty, isTrue);
    });

    test('replaces the ordering with the clicked field alone', () {
      final sort = ListSort.empty
          .cycle('status')
          .cycle('name', additive: true)
          .cycle('id', additive: true);

      expect(sort.cycle('due_date'), const ListSort([SortKey('due_date')]));
    });

    test('advances the phase of a field that was a secondary level', () {
      // The case a naive implementation gets wrong: dropping the other levels
      // is right, but restarting at ascending costs one more click to reach the
      // order the user was already asking for.
      final sort = ListSort.empty.cycle('status').cycle('name', additive: true);

      expect(
        sort.cycle('name'),
        const ListSort([SortKey('name', ascending: false)]),
      );
    });

    test('a secondary descending level clears the ordering', () {
      final sort = ListSort.empty
          .cycle('status')
          .cycle('name', additive: true)
          .cycle('name', additive: true);

      expect(sort.cycle('name').isEmpty, isTrue);
    });
  });

  group('additive click', () {
    test('appends a level as the last one', () {
      final sort = ListSort.empty.cycle('status').cycle('name', additive: true);

      expect(sort.keys.map((key) => key.field), ['status', 'name']);
      expect(sort.rankOf('name'), 2);
    });

    test('flips an existing level in place, keeping its rank', () {
      final sort = ListSort.empty
          .cycle('status')
          .cycle('name', additive: true)
          .cycle('id', additive: true)
          .cycle('name', additive: true);

      expect(sort.keys.map((key) => key.field), ['status', 'name', 'id']);
      expect(sort.rankOf('name'), 2);
      expect(sort.keyFor('name')!.ascending, isFalse);
    });

    test('removes a descending level and renumbers the ones below', () {
      final sort = ListSort.empty
          .cycle('status')
          .cycle('name', additive: true)
          .cycle('id', additive: true)
          .cycle('name', additive: true)
          .cycle('name', additive: true);

      expect(sort.keys.map((key) => key.field), ['status', 'id']);
      expect(sort.rankOf('status'), 1);
      expect(sort.rankOf('id'), 2);
      expect(sort.rankOf('name'), isNull);
    });

    test('never promotes an existing level to primary', () {
      final sort = ListSort.empty.cycle('status').cycle('name', additive: true);

      expect(sort.cycle('name', additive: true).keys.first.field, 'status');
    });
  });

  group('order_by', () {
    test('is always explicit about the direction', () {
      final sort = ListSort.empty
          .cycle('status')
          .cycle('name', additive: true)
          .cycle('name', additive: true);

      expect(sort.toOrderBy(), ['status:asc', 'name:desc']);
    });

    test('is empty when nothing is sorted, leaving the server default', () {
      expect(ListSort.empty.toOrderBy(), isEmpty);
    });
  });

  group('encode / decode', () {
    test('round trips, dotted paths included', () {
      final sort = ListSort.empty
          .cycle('status.name')
          .cycle('due_date', additive: true)
          .cycle('due_date', additive: true);

      expect(sort.encode(), 'status.name,-due_date');
      expect(ListSort.decode(sort.encode()), sort);
    });

    test('reads an empty or absent value as no ordering', () {
      expect(ListSort.decode(null), ListSort.empty);
      expect(ListSort.decode(''), ListSort.empty);
      expect(ListSort.decode('  '), ListSort.empty);
      expect(ListSort.decode(',,'), ListSort.empty);
    });

    test('drops what allow refuses instead of failing', () {
      final sort = ListSort.decode(
        'name,-secret,id',
        allow: (field) => field != 'secret',
      );

      expect(sort.keys.map((key) => key.field), ['name', 'id']);
    });

    test('survives a malformed value', () {
      expect(ListSort.decode('-').isEmpty, isTrue);
      expect(ListSort.decode(' name , , -id ').keys.map((k) => k.field), [
        'name',
        'id',
      ]);
    });

    test('keeps the first mention of a repeated field', () {
      final sort = ListSort.decode('name,-name');

      expect(sort.keys.length, 1);
      expect(sort.keyFor('name')!.ascending, isTrue);
    });
  });

  group('equality', () {
    test('is sensitive to the level order', () {
      const a = ListSort([SortKey('status'), SortKey('name')]);
      const b = ListSort([SortKey('name'), SortKey('status')]);

      expect(a == b, isFalse);
      expect(a == const ListSort([SortKey('status'), SortKey('name')]), isTrue);
    });

    test('is sensitive to the direction', () {
      expect(
        const ListSort([SortKey('name')]) ==
            const ListSort([SortKey('name', ascending: false)]),
        isFalse,
      );
    });

    test('hashes equal orderings alike', () {
      expect(
        const ListSort([SortKey('a'), SortKey('b')]).hashCode,
        const ListSort([SortKey('a'), SortKey('b')]).hashCode,
      );
    });
  });
}
