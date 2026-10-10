/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ordering of a list', () {
    test('reads an ordering written as one string', () {
      expect(parseOrderBy('name:asc, created_at:desc'), [
        'name:asc',
        'created_at:desc',
      ]);
      expect(parseOrderBy('name'), ['name']);
    });

    test('says nothing for an ordering nobody asked for', () {
      expect(parseOrderBy(null), isNull);
      expect(parseOrderBy(''), isNull);
      expect(formatOrderBy([]), isNull);
      expect(formatOrderBy(null), isNull);
    });

    test('writes an ordering back as one string', () {
      expect(
        formatOrderBy(['name:asc', 'created_at:desc']),
        'name:asc,created_at:desc',
      );
    });

    test('reads the field a term names, ascending without a direction', () {
      expect(orderByTerm('name:desc'), (field: 'name', direction: 'desc'));
      expect(orderByTerm('name'), (field: 'name', direction: 'asc'));
    });
  });
}
