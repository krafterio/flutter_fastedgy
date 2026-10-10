/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// A day shifted by the time zone is what these tests are for: run them under
// a zone west of UTC and one east of it too, e.g. `TZ=Pacific/Auckland flutter
// test test/query/dates_test.dart`.

import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const day = '2026-10-08';
  const on = OperatorOption('on', 'between', 'on');
  const range = OperatorOption('between', 'between', 'between');

  OperatorOption option(String id) => OperatorOption(id, id, id);

  group('the instants of a local day', () {
    test('are its first and its last, written in UTC', () {
      expect(dayStart(day), DateTime(2026, 10, 8).toUtc().toIso8601String());
      expect(
        dayEnd(day),
        DateTime(2026, 10, 8, 23, 59, 59, 999).toUtc().toIso8601String(),
      );
      expect(dayStart(day), endsWith('Z'));
      expect(DateTime.parse(dayStart(day)!).toLocal(), DateTime(2026, 10, 8));
      expect(dayStart('8 October'), isNull);
      expect(dayEnd(null), isNull);
    });

    test('fall on that day, and so does a late hour of it', () {
      final late = DateTime(2026, 10, 8, 23, 30).toUtc().toIso8601String();

      expect(dayOf(dayStart(day)), day);
      expect(dayOf(dayEnd(day)), day);
      expect(dayOf(late), day);
      expect(dayOf(day), day);
      expect(dayOf('soon'), isNull);
      expect(dayOf(null), isNull);
    });

    test('read back as one day only when a range covers exactly one', () {
      expect(coversOneDay([dayStart(day), dayEnd(day)]), isTrue);
      expect(coversOneDay([dayStart(day), dayEnd('2026-10-09')]), isFalse);
      expect(coversOneDay([dayStart(day), 'soon']), isFalse);
      expect(coversOneDay([dayStart(day)]), isFalse);
      expect(coversOneDay(day), isFalse);
    });
  });

  group('a datetime filtered on days', () {
    test('is written as the instants of the days picked', () {
      expect(datetimeValue(on, [day]), [dayStart(day), dayEnd(day)]);
      expect(datetimeValue(range, [day, '2026-10-09']), [
        dayStart(day),
        dayEnd('2026-10-09'),
      ]);
      expect(datetimeValue(option('<'), [day]), dayStart(day));
      expect(datetimeValue(option('>='), [day]), dayStart(day));
      expect(datetimeValue(option('<='), [day]), dayEnd(day));
      expect(datetimeValue(option('>'), [day]), dayEnd(day));
      expect(datetimeValue(range, []), isEmpty);
      expect(datetimeValue(option('<'), [null]), isNull);
    });

    test('shows back the days it stands for', () {
      expect(datetimeDays(on, [dayStart(day), dayEnd(day)]), [day, day]);
      expect(datetimeDays(option('<'), dayStart(day)), [day]);
      expect(datetimeDays(range, null), isEmpty);
    });
  });
}
