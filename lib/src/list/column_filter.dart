/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:intl/intl.dart';

import '../api/api_query.dart';
import '../api/list_filter.dart';
import '../i18n/i18n.dart';
import '../metadata/models.dart';
import '../query/catalog.dart';
import '../query/dates.dart';
import '../query/query_expression.dart';
import '../query/registry.dart';

/// Rules all applying, `[field, operator, value]` or a group of them.
typedef FilterRules = List<List<Object?>>;

/// What applies at the first level of [expression], each item holding with
/// the others: its items when it is a group of all of them, itself otherwise.
List<Object?> _items(Object? expression) {
  final written = serializeExpression(parseExpression(expression));

  if (written == null) {
    return const [];
  }

  if (written case ['&', final List items]) {
    return items;
  }

  return [written];
}

bool _isOn(Object? item, String field) =>
    item is List && ListFilter.fieldOf(item) == field;

/// The rules of [field] at the first level of [expression]: what a column
/// filter reads.
FilterRules columnRules(Object? expression, String field) => [
  for (final item in _items(expression))
    if (_isOn(item, field)) item as List<Object?>,
];

/// [expression] with [rules] in place of the rules of [field] at its first
/// level, all of them applying with the rest.
Object? withColumnRules(Object? expression, String field, FilterRules rules) {
  final items = [
    for (final item in _items(expression))
      if (!_isOn(item, field)) item,
    ...rules,
  ];

  if (items.isEmpty) {
    return null;
  }

  return items.length == 1 ? items.single : ['&', items];
}

/// The filter of a column, the port of melimelo's `TableFilter`: the rules of
/// one field at the first level of the expression of a list, read as a value
/// [V] and written back. Its editor is drawn by flutter_fastedgy_ui.
abstract class ColumnFilter<V extends Object> {
  const ColumnFilter(this.field, this.label);

  final String field;
  final String label;

  /// The value [rules] stand for, null when they say nothing this filter
  /// reads.
  V? read(FilterRules rules);

  /// The rules [value] stands for, none for null.
  FilterRules write(V? value);

  /// [value] in words, after the label in a chip.
  String describe(V value);

  /// The value of this filter in [expression].
  V? valueIn(Object? expression) => read(columnRules(expression, field));

  /// [expression] with this filter set to [value], or cleared for null.
  Object? applyTo(Object? expression, V? value) =>
      withColumnRules(expression, field, write(value));
}

/// The text a field contains.
class TextColumnFilter extends ColumnFilter<String> {
  const TextColumnFilter(super.field, super.label);

  @override
  String? read(FilterRules rules) => [
    for (final rule in rules)
      if (rule case [_, 'icontains', final String text]) text,
  ].firstOrNull;

  @override
  FilterRules write(String? value) {
    final text = value?.trim() ?? '';

    return [
      if (text.isNotEmpty) [field, 'icontains', text],
    ];
  }

  @override
  String describe(String value) => value;
}

/// The bounds of a number, both included.
typedef NumberBounds = ({num? min, num? max});

/// A number between two bounds, either one left open.
class NumberRangeColumnFilter extends ColumnFilter<NumberBounds> {
  const NumberRangeColumnFilter(super.field, super.label);

  @override
  NumberBounds? read(FilterRules rules) {
    num? min;
    num? max;

    for (final rule in rules) {
      switch (rule) {
        case [_, '>=', final num value]:
          min = value;
        case [_, '<=', final num value]:
          max = value;
      }
    }

    return min == null && max == null ? null : (min: min, max: max);
  }

  @override
  FilterRules write(NumberBounds? value) => [
    if (value?.min case final num min) [field, '>=', min],
    if (value?.max case final num max) [field, '<=', max],
  ];

  @override
  String describe(NumberBounds value) {
    final format = NumberFormat.decimalPattern();
    final (:min, :max) = value;

    if (min != null && max != null) {
      return '${format.format(min)} – ${format.format(max)}';
    }

    return min != null
        ? t('at least {value}', {'value': format.format(min)})
        : t('at most {value}', {'value': format.format(max!)});
  }
}

/// The days of a period, `YYYY-MM-DD`, both included.
typedef DayBounds = ({String? from, String? to});

String _nextDay(String day) {
  final date = DateTime.parse(day);

  return _day(DateTime(date.year, date.month, date.day + 1));
}

String _previousDay(String day) {
  final date = DateTime.parse(day);

  return _day(DateTime(date.year, date.month, date.day - 1));
}

String _day(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The days a date falls between, either one left open: from the first day
/// (`>=`) to the end of the last one (`<` the next day). A [datetime] is
/// compared with the instants that start those local days.
class DateRangeColumnFilter extends ColumnFilter<DayBounds> {
  const DateRangeColumnFilter(
    super.field,
    super.label, {
    this.datetime = false,
  });

  final bool datetime;

  @override
  DayBounds? read(FilterRules rules) {
    String? from;
    String? to;

    for (final rule in rules) {
      if (rule case [_, final String operator, final String value]) {
        final day = dayOf(value);

        if (day == null) {
          continue;
        }

        if (operator == '>=') {
          from = day;
        } else if (operator == '<') {
          to = _previousDay(day);
        }
      }
    }

    return from == null && to == null ? null : (from: from, to: to);
  }

  String? _bound(String day) => datetime ? dayStart(day) : day;

  @override
  FilterRules write(DayBounds? value) => [
    if (value?.from case final String from) [field, '>=', _bound(from)],
    if (value?.to case final String to) [field, '<', _bound(_nextDay(to))],
  ];

  @override
  String describe(DayBounds value) {
    String shown(String day) => DateFormat.yMMMd().format(DateTime.parse(day));
    final (:from, :to) = value;

    if (from != null && to != null) {
      return '${shown(from)} – ${shown(to)}';
    }

    return from != null
        ? t('from {date}', {'date': shown(from)})
        : t('until {date}', {'date': shown(to!)});
  }
}

/// The values [rules] choose: `in` them, `=` one, `is empty` for null.
Set<Object?>? _readValues(FilterRules rules) {
  final chosen = <Object?>{};

  void take(Object? rule) {
    switch (rule) {
      case [_, 'is empty']:
        chosen.add(null);
      case [_, 'in', final List values]:
        chosen.addAll(values);
      case [_, '=', final Object value]:
        chosen.add(value);
    }
  }

  for (final rule in rules) {
    if (rule case ['|', final List inner]) {
      inner.forEach(take);
    } else {
      take(rule);
    }
  }

  return chosen.isEmpty ? null : chosen;
}

/// The rules choosing [value] on [field], « no value » for null.
FilterRules _writeValues(String field, Set<Object?>? value) {
  final values = [...?value?.whereType<Object>()];
  final empty = value?.contains(null) ?? false;

  if (values.isEmpty) {
    return [
      if (empty) [field, 'is empty'],
    ];
  }

  if (!empty) {
    return [
      [field, 'in', values],
    ];
  }

  return [
    [
      '|',
      [
        [field, 'in', values],
        [field, 'is empty'],
      ],
    ],
  ];
}

/// A value offered by a choice filter, null standing for no value.
class ColumnFilterOption {
  const ColumnFilterOption(this.value, this.label);

  final Object? value;
  final String label;
}

/// Values among [options], « no value » included when one of them is null:
/// `in`, with `is empty` as an alternative.
class ChoiceColumnFilter extends ColumnFilter<Set<Object?>> {
  const ChoiceColumnFilter(super.field, super.label, {required this.options});

  final List<ColumnFilterOption> options;

  @override
  Set<Object?>? read(FilterRules rules) => _readValues(rules);

  @override
  FilterRules write(Set<Object?>? value) => _writeValues(field, value);

  @override
  String describe(Set<Object?> value) => [
    for (final option in options)
      if (value.contains(option.value)) option.label,
  ].join(', ');
}

/// Records of a relation, « no value » included when the set holds null:
/// `in` their ids, with `is empty` as an alternative. The records come from
/// [source], which an editor lists and searches; the chips name those it
/// [remember]s or resolves, `#id` the others.
class RelationColumnFilter extends ColumnFilter<Set<Object?>> {
  RelationColumnFilter(super.field, super.label, {required this.source});

  final ValueSource source;

  final _labels = <Object?, String>{};

  @override
  Set<Object?>? read(FilterRules rules) => _readValues(rules);

  @override
  FilterRules write(Set<Object?>? value) => _writeValues(field, value);

  @override
  String describe(Set<Object?> value) =>
      [for (final id in value) id == null ? t('Empty') : _labels[id] ?? '#$id']
          .join(', ');

  /// Names the record [id] in the chips, as the editor showing it does.
  void remember(Object id, String label) => _labels[id] = label;

  /// Reads the records of [ids] not named yet, to name them in the chips.
  Future<void> resolveLabels(Iterable<Object?> ids) async {
    final reader = source.reader;
    final label = source.label;

    if (reader == null || label == null) {
      return;
    }

    for (final id in ids) {
      if (id == null || _labels.containsKey(id)) {
        continue;
      }

      try {
        final record = await reader.get(
          id,
          options: FieldsOptions(fields: ['id', ...?source.fields]),
        );

        _labels[id] = label(record.data);
      } catch (_) {
        // Unread, it stays `#id`.
      }
    }
  }
}

/// The filter of a column on [field], by the kind of the field: a text, the
/// bounds of a number or of a date, values among its choices, records of a
/// relation read through the value source of its model in [context]. Null
/// for a kind no column filter reads.
ColumnFilter<Object>? columnFilterOf(
  MetadataField field, {
  String? label,
  ValueSourceContext? context,
}) {
  final title = label ?? field.label;
  final target = field.target;

  return switch (kindOf(field)) {
    FieldKind.text => TextColumnFilter(field.name, title),
    FieldKind.number => NumberRangeColumnFilter(field.name, title),
    FieldKind.date => DateRangeColumnFilter(field.name, title),
    FieldKind.datetime => DateRangeColumnFilter(
      field.name,
      title,
      datetime: true,
    ),
    FieldKind.choice => ChoiceColumnFilter(
      field.name,
      title,
      options: [
        for (final MapEntry(:key, :value)
            in (field.choices ?? const <String, String>{}).entries)
          ColumnFilterOption(key, value),
        if (!field.required) ColumnFilterOption(null, t('Empty')),
      ],
    ),
    FieldKind.single || FieldKind.multiple
        when target != null && context != null =>
      RelationColumnFilter(
        field.name,
        title,
        source: resolveValueSource(target, context),
      ),
    _ => null,
  };
}
