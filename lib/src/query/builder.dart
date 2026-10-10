/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../metadata/models.dart';
import 'catalog.dart';
import 'query_expression.dart';
import 'query_fields.dart';

// What the query builder of vue-fastedgy writes in its components, as
// functions every drawing of it shares: the popover, the full screen, and an
// application putting the parts together its own way.

const _accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
const _plain = 'aaaaaaceeeeiiiinooooouuuuyy';

/// A text without its case nor its accents, to compare what a person types
/// with a label: the accents of the Latin-1 letters, those of the languages
/// the package speaks, and the combining ones.
String foldText(String? text) {
  final folded = StringBuffer();

  for (final rune in (text ?? '').toLowerCase().runes) {
    if (rune >= 0x300 && rune <= 0x36f) {
      continue;
    }

    final char = String.fromCharCode(rune);
    final index = _accented.indexOf(char);

    folded.write(index < 0 ? char : _plain[index]);
  }

  return folded.toString();
}

/// A field the field picker offers.
class FieldEntry {
  const FieldEntry({
    required this.path,
    required this.label,
    required this.field,
    required this.relation,
  });

  /// The path from the model of the condition, `owner.email`.
  final String path;

  final String label;
  final MetadataField field;

  /// Whether it can be entered: a relation whose model the metadata describe.
  final bool relation;
}

List<String> _names(String path) => [
  for (final name in path.split('.'))
    if (name.isNotEmpty) name,
];

String? _modelAt(
  Map<String, MetadataModel> metadatas,
  String model,
  List<String> walked,
) => walked.fold<String?>(
  model,
  (current, name) => metadatas[current]?.fields[name]?.target,
);

int _byLabel(FieldEntry a, FieldEntry b) {
  final folded = foldText(a.label).compareTo(foldText(b.label));

  return folded != 0 ? folded : a.label.compareTo(b.label);
}

/// The relation leading back through the last of the relations [walked] from
/// [model]: the level it opens does not offer it.
String? backAt(
  Map<String, MetadataModel> metadatas,
  String model,
  List<String> walked,
) {
  String? current = model;
  MetadataField? field;

  for (final name in walked) {
    field = metadatas[current]?.fields[name];
    current = field?.target;
  }

  return field?.inverse;
}

/// The fields offered at one level of the walk from [model], the model of the
/// list: the level reached through [path], the relations of the blocks
/// around, then through the relations entered ([levels]). Sorted by label,
/// without the relation leading back nor the [exclude]d paths.
List<FieldEntry> fieldsAt(
  Map<String, MetadataModel> metadatas,
  String model, {
  String path = '',
  List<String> levels = const [],
  List<String> exclude = const [],
}) {
  final walked = [..._names(path), ...levels];
  final back = backAt(metadatas, model, walked);
  final fields = filterableFields(
    metadatas[_modelAt(metadatas, model, walked)],
    exclude: exclude,
    prefix: walked.join('.'),
  );

  return [
    for (final field in fields)
      if (field.name != back)
        FieldEntry(
          path: [...levels, field.name].join('.'),
          label: field.label,
          field: field,
          relation:
              relationKindOf(field) != null &&
              metadatas.containsKey(field.target),
        ),
  ]..sort(_byLabel);
}

/// What a search from the first level finds one level down its single
/// relations, matching [text]: « Relation › Field », chosen without entering
/// the relation.
List<FieldEntry> deepFields(
  Map<String, MetadataModel> metadatas,
  String model,
  String text, {
  String path = '',
  List<String> exclude = const [],
}) {
  final folded = foldText(text);

  return [
    for (final relation in fieldsAt(
      metadatas,
      model,
      path: path,
      exclude: exclude,
    ))
      if (relation.relation &&
          relationKindOf(relation.field) == FieldKind.single)
        for (final entry in fieldsAt(
          metadatas,
          model,
          path: path,
          levels: [relation.field.name],
          exclude: exclude,
        ))
          if (foldText(entry.label).contains(folded))
            FieldEntry(
              path: entry.path,
              label: '${relation.label} › ${entry.label}',
              field: entry.field,
              relation: false,
            ),
  ];
}

/// The walk of the field picker through the relations of the model of a
/// list, for the condition of a block at [path]: the relations entered, the
/// search, the entries and the crumbs. A chevron [enter]s a relation, its
/// name [choose]s it.
class FieldPicker extends ChangeNotifier {
  FieldPicker({
    required this.metadatas,
    required this.model,
    this.path = '',
    this.exclude = const [],
    this.deepFieldSearch = false,
  });

  final Map<String, MetadataModel> metadatas;

  /// The model of the list.
  final String model;

  /// The relation path of the block the condition sits in.
  final String path;

  final List<String> exclude;

  /// Whether a search from the first level also finds the fields of its
  /// single relations.
  final bool deepFieldSearch;

  List<String> _levels = const [];
  String _search = '';

  /// The relations entered, from the model of the condition.
  List<String> get levels => _levels;

  String get search => _search;

  set search(String value) {
    _search = value;
    notifyListeners();
  }

  /// The model the conditions of the block are on.
  String? get _conditionModel => _modelAt(metadatas, model, _names(path));

  /// The fields of the level matching the search, and, from the first level
  /// with [deepFieldSearch], those one level down its single relations.
  List<FieldEntry> get entries {
    final own = fieldsAt(
      metadatas,
      model,
      path: path,
      levels: _levels,
      exclude: exclude,
    );
    final text = foldText(_search);

    if (text.isEmpty) {
      return own;
    }

    final matching = [
      for (final entry in own)
        if (foldText(entry.label).contains(text)) entry,
    ];

    if (!deepFieldSearch || _levels.isNotEmpty) {
      return matching;
    }

    return [
      ...matching,
      ...deepFields(metadatas, model, _search, path: path, exclude: exclude),
    ];
  }

  /// The label of the model of the condition, then of each relation entered.
  List<String> get crumbs {
    var current = _conditionModel;
    final crumbs = [metadatas[current]?.label ?? current ?? model];

    for (final name in _levels) {
      final field = metadatas[current]?.fields[name];

      crumbs.add(field?.label ?? name);
      current = field?.target;
    }

    return crumbs;
  }

  /// Opens the fields of the relation [entry].
  void enter(FieldEntry entry) {
    _levels = [..._levels, entry.field.name];
    _search = '';
    notifyListeners();
  }

  /// Goes back up one level.
  void back() {
    if (_levels.isEmpty) {
      return;
    }

    _levels = _levels.sublist(0, _levels.length - 1);
    notifyListeners();
  }

  /// Puts the field [entry] on [rule], keeping what can be kept
  /// ([keepOnFieldChange]).
  void choose(QueryExpression query, QueryRule rule, FieldEntry entry) {
    final before = resolveFieldPath(
      metadatas,
      _conditionModel ?? model,
      rule.field,
    )?.field;
    final next = keepOnFieldChange(metadatas, before, entry.field, rule);

    query.update(
      rule.id,
      field: entry.path,
      operator: next.operator,
      value: next.value,
      ui: next.ui,
    );
  }
}

/// Whether a condition on [model] shows as written, read only: what the
/// editor does not read, a field the metadata do not describe once they are
/// there, or an operator the field does not offer.
bool isReadOnlyRule(
  Map<String, MetadataModel>? metadatas,
  String model,
  QueryNode node,
) {
  if (node is QueryOpaque) {
    return true;
  }

  if (node is! QueryRule || metadatas == null || node.field.isEmpty) {
    return false;
  }

  final resolved = resolveFieldPath(metadatas, model, node.field);

  return resolved == null ||
      (node.operator.isNotEmpty &&
          optionOfRule(operatorOptions(metadatas, resolved.field), node) ==
              null);
}

/// Whether a condition under [option] takes a value: an operator is chosen,
/// and it is neither « is empty » nor a block.
bool hasValue(OperatorOption? option) =>
    option != null &&
    !const [Arity.none, Arity.sub].contains(arityOf(option.operator));

/// Chooses [option] on a block: « at least one » and « none » switch it, any
/// other operator folds it back into a condition on its relation. Returns
/// false, changing nothing, while the block holds conditions and the fold is
/// not [confirmed]: the caller asks first.
bool foldAnyBlock(
  QueryExpression query,
  QueryAnyBlock block,
  OperatorOption option, {
  bool confirmed = false,
}) {
  if (option.operator == 'any' || option.operator == 'not any') {
    query.update(block.id, negated: option.operator == 'not any');

    return true;
  }

  if (block.group.children.isNotEmpty && !confirmed) {
    return false;
  }

  query.replace(block.id, QueryRule(block.field, option.operator));

  return true;
}

/// The title of a block on [model]: the key of its text, and the relation it
/// names in it (`{relation}`), « Members » or « Owner › Company ».
({String key, String relation}) anyBlockTitle(
  Map<String, MetadataModel>? metadatas,
  String model,
  QueryAnyBlock block,
) {
  final resolved = resolveFieldPath(metadatas, model, block.field);
  final single = relationKindOf(resolved?.field) == FieldKind.single;

  return (
    key: switch ((single, block.negated)) {
      (true, false) => '{relation}: matching…',
      (true, true) => '{relation}: not matching…',
      (false, false) => '{relation}: at least one that…',
      (false, true) => '{relation}: none that…',
    },
    relation:
        resolved?.chain.map((link) => link.field.label).join(' › ') ??
        block.field,
  );
}

/// A number typed in, or null when it does not read as one.
num? readNumber(Object? value) {
  final number = value is num ? value : num.tryParse('${value ?? ''}'.trim());

  return number != null && number.isFinite ? number : null;
}

bool _numeric(FieldKind? kind) =>
    kind == FieldKind.number || kind == FieldKind.single;

/// The values of a list typed in as tags: numbers for a number or a relation,
/// trimmed texts otherwise, without what is empty or does not read.
List<Object> parseListInput(Iterable<String> values, FieldKind? kind) => [
  for (final value in values)
    ?(_numeric(kind)
        ? readNumber(value)
        : (value.trim().isEmpty ? null : value.trim())),
];

/// Both ends of a range typed in: numbers for a number or a relation, the
/// text otherwise, null for an end left empty.
List<Object?> rangeValue(List<String> ends, FieldKind? kind) => [
  for (final end in ends)
    _numeric(kind) ? readNumber(end) : (end.isEmpty ? null : end),
];

/// The value of a reference to a record of [model]: `[model, id]`, a list of
/// them when [multiple], or null when nothing is chosen.
Object? referenceValue(String model, Object? chosen, {required bool multiple}) {
  if (multiple) {
    return [
      for (final id in chosen is List ? chosen : const []) [model, id],
    ];
  }

  return chosen == null ? null : [model, chosen];
}
