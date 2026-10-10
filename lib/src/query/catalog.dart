/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../metadata/models.dart';
import 'dates.dart';
import 'query_expression.dart';
import 'query_fields.dart';

/// What kind of value a field holds, as the catalog groups them.
enum FieldKind {
  text,
  number,
  date,
  datetime,
  time,
  boolean,
  choice,

  /// A relation to one record.
  single,

  /// A relation to several records.
  multiple,

  /// A record of one model among several, `[model, id]`.
  reference,

  /// Content only ever empty or not.
  content,
}

const _kinds = {
  'char': FieldKind.text,
  'text': FieldKind.text,
  'email': FieldKind.text,
  'uuid': FieldKind.text,
  'url': FieldKind.text,
  'u_r_l': FieldKind.text,
  'integer': FieldKind.number,
  'small_integer': FieldKind.number,
  'big_integer': FieldKind.number,
  'float': FieldKind.number,
  'decimal': FieldKind.number,
  'date': FieldKind.date,
  'datetime': FieldKind.datetime,
  'date_time': FieldKind.datetime,
  'time': FieldKind.time,
  'boolean': FieldKind.boolean,
  'choice': FieldKind.choice,
  'char_choice': FieldKind.choice,
  'many2one': FieldKind.single,
  'one2one': FieldKind.single,
  'one_to_one': FieldKind.single,
  'one2many': FieldKind.multiple,
  'many2many': FieldKind.multiple,
  'reference': FieldKind.reference,
  'many2one_ref': FieldKind.reference,
  'json': FieldKind.content,
  'binary': FieldKind.content,
};

/// The kind of [field]: a field with choices is a choice unless it is a
/// relation, and an unknown type is a text when it is searched as one.
FieldKind? kindOf(MetadataField? field) {
  if (field == null) {
    return null;
  }

  final kind = _kinds[field.type];

  if ((field.choices?.isNotEmpty ?? false) &&
      kind != FieldKind.single &&
      kind != FieldKind.multiple) {
    return FieldKind.choice;
  }

  return kind ??
      (field.filterOperators.contains('icontains')
          ? FieldKind.text
          : FieldKind.content);
}

/// An operator the menu offers.
class OperatorOption {
  const OperatorOption(this.id, this.operator, this.label);

  /// What the menu selects: the operator, or `on` for a datetime on a day.
  final String id;

  /// What the expression carries.
  final String operator;

  /// The English text, the key of its translation where it is shown.
  final String label;
}

const _empty = [
  OperatorOption('is empty', 'is empty', 'is empty'),
  OperatorOption('is not empty', 'is not empty', 'is not empty'),
];

/// The operators offered by kind, in the order offered, crossed with what the
/// server accepts on the field, which stays the authority.
const _offers = {
  FieldKind.text: [
    OperatorOption('icontains', 'icontains', 'contains'),
    OperatorOption('not icontains', 'not icontains', 'does not contain'),
    OperatorOption('=', '=', 'is'),
    OperatorOption('!=', '!=', 'is not'),
    OperatorOption('starts with', 'starts with', 'starts with'),
    OperatorOption('ends with', 'ends with', 'ends with'),
    OperatorOption('in', 'in', 'is one of'),
    OperatorOption('not in', 'not in', 'is none of'),
    ..._empty,
  ],
  FieldKind.number: [
    OperatorOption('=', '=', 'is'),
    OperatorOption('!=', '!=', 'is not'),
    OperatorOption('<', '<', 'less than'),
    OperatorOption('<=', '<=', 'at most'),
    OperatorOption('>', '>', 'greater than'),
    OperatorOption('>=', '>=', 'at least'),
    OperatorOption('between', 'between', 'between'),
    OperatorOption('in', 'in', 'is one of'),
    OperatorOption('not in', 'not in', 'is none of'),
    ..._empty,
  ],
  FieldKind.date: [
    OperatorOption('=', '=', 'on'),
    OperatorOption('!=', '!=', 'not on'),
    OperatorOption('<', '<', 'before'),
    OperatorOption('<=', '<=', 'until'),
    OperatorOption('>', '>', 'after'),
    OperatorOption('>=', '>=', 'from'),
    OperatorOption('between', 'between', 'between'),
    ..._empty,
  ],
  FieldKind.datetime: [
    OperatorOption('on', 'between', 'on'),
    OperatorOption('<', '<', 'before'),
    OperatorOption('<=', '<=', 'until'),
    OperatorOption('>', '>', 'after'),
    OperatorOption('>=', '>=', 'from'),
    OperatorOption('between', 'between', 'between'),
    ..._empty,
  ],
  FieldKind.time: [
    OperatorOption('=', '=', 'is'),
    OperatorOption('<', '<', 'earlier than'),
    OperatorOption('<=', '<=', 'at the latest'),
    OperatorOption('>', '>', 'later than'),
    OperatorOption('>=', '>=', 'at the earliest'),
    OperatorOption('between', 'between', 'between'),
    ..._empty,
  ],
  FieldKind.boolean: [
    OperatorOption('is true', 'is true', 'is true'),
    OperatorOption('is false', 'is false', 'is false'),
  ],
  FieldKind.choice: [
    OperatorOption('=', '=', 'is'),
    OperatorOption('!=', '!=', 'is not'),
    OperatorOption('in', 'in', 'is one of'),
    OperatorOption('not in', 'not in', 'is none of'),
    ..._empty,
  ],
  FieldKind.single: [
    OperatorOption('=', '=', 'is'),
    OperatorOption('!=', '!=', 'is not'),
    OperatorOption('in', 'in', 'is one of'),
    OperatorOption('not in', 'not in', 'is none of'),
    ..._empty,
    OperatorOption('any', 'any', 'matches…'),
    OperatorOption('not any', 'not any', 'does not match…'),
    OperatorOption('<', '<', 'id less than'),
    OperatorOption('<=', '<=', 'id at most'),
    OperatorOption('>', '>', 'id greater than'),
    OperatorOption('>=', '>=', 'id at least'),
    OperatorOption('between', 'between', 'id between'),
  ],
  FieldKind.multiple: [
    OperatorOption('in', 'in', 'contains one of'),
    OperatorOption('not in', 'not in', 'contains none of'),
    ..._empty,
    OperatorOption('any', 'any', 'has at least one that…'),
    OperatorOption('not any', 'not any', 'has none that…'),
  ],
  FieldKind.reference: [
    OperatorOption('=', '=', 'is'),
    OperatorOption('!=', '!=', 'is not'),
    OperatorOption('in', 'in', 'is one of'),
    OperatorOption('not in', 'not in', 'is none of'),
    ..._empty,
  ],
  FieldKind.content: _empty,
};

/// The operators [field] offers, in the catalog's order.
List<OperatorOption> operatorOptions(
  Map<String, MetadataModel>? metadatas,
  MetadataField? field,
) {
  final accepted = fieldOperators(metadatas, field);

  return [
    for (final option in _offers[kindOf(field)] ?? const <OperatorOption>[])
      if (accepted.contains(option.operator)) option,
  ];
}

/// The option [rule] stands for: its operator, except a datetime range read
/// as « on », which [QueryRule.ui] says, or, without it, a range covering
/// exactly one local day.
OperatorOption? optionOfRule(List<OperatorOption> options, QueryRule rule) {
  final on = options.where((option) => option.id == 'on').firstOrNull;

  if (on != null &&
      rule.operator == 'between' &&
      (rule.ui == 'on' || (rule.ui == null && coversOneDay(rule.value)))) {
    return on;
  }

  return options
      .where((option) => option.id != 'on' && option.operator == rule.operator)
      .firstOrNull;
}

List<String?> _daysOf(OperatorOption option, Object? value) {
  if (option.operator == 'between') {
    return value is List ? [for (final one in value) dayOf(one)] : [];
  }

  return [dayOf(value)];
}

Object? _encodeDays(OperatorOption option, List<String?> days) {
  final first = days.firstOrNull;
  final last = days.length > 1 ? days[1] : first;

  if (first == null || first.isEmpty) {
    return option.operator == 'between' ? <String?>[] : null;
  }

  return switch (option.id) {
    'on' => [dayStart(first), dayEnd(first)],
    'between' => [dayStart(first), dayEnd(last)],
    '<' || '>=' => dayStart(first),
    _ => dayEnd(first),
  };
}

/// A datetime option written from the days a person picked: « on » and
/// « between » as ranges of whole days, `<` and `>=` from the first instant
/// of the day, `<=` and `>` from its last.
Object? datetimeValue(OperatorOption option, List<String?> days) =>
    _encodeDays(option, days);

/// The days a datetime rule stands for, to show them back.
List<String?> datetimeDays(OperatorOption option, Object? value) =>
    _daysOf(option, value);

/// What a value becomes when the operator changes: kept for the same arity,
/// one value turned into a list of one and back, re-encoded for a datetime,
/// emptied otherwise. Retyping the value after hesitating between two
/// operators is what this spares.
Object? convertValue(
  FieldKind? kind,
  OperatorOption from,
  OperatorOption to,
  Object? value,
) {
  if (kind == FieldKind.datetime) {
    return _encodeDays(to, _daysOf(from, value));
  }

  final before = arityOf(from.operator);
  final after = arityOf(to.operator);

  if (before == after) {
    return value;
  }

  if (before == Arity.one && after == Arity.list) {
    return value == null || value == '' ? <Object?>[] : [value];
  }

  if (before == Arity.list && after == Arity.one) {
    return value is List ? value.firstOrNull : value;
  }

  return null;
}

/// What a rule keeps when its field changes from [before] to [after]: its
/// operator if the new field offers it, its value too if the kind is the
/// same; the first operator of the field otherwise.
({String operator, Object? value, String? ui}) keepOnFieldChange(
  Map<String, MetadataModel>? metadatas,
  MetadataField? before,
  MetadataField after,
  QueryRule rule,
) {
  final options = operatorOptions(metadatas, after);
  final kept = rule.operator.isEmpty ? null : optionOfRule(options, rule);
  final option = kept ?? options.firstOrNull;

  if (option == null) {
    return (operator: '', value: null, ui: null);
  }

  return (
    operator: option.operator,
    value: kept != null && kindOf(before) == kindOf(after) ? rule.value : null,
    ui: option.id == 'on' ? 'on' : null,
  );
}
