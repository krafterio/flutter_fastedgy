/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'filter_ast.dart';
import 'local_schema.dart';

/// A field a query filters or orders on whose column no read ever populated.
class UnmirroredQueryField {
  /// Path as written in the query (`user`, `favorites.user`).
  final String path;

  /// Model holding the column.
  final String model;

  /// Column that stayed empty.
  final String column;

  const UnmirroredQueryField({
    required this.path,
    required this.model,
    required this.column,
  });

  @override
  String toString() => '$path ($model.$column)';
}

/// Field paths a filter reads, deduplicated.
///
/// The sub-filter of an `any` rule is walked too, its paths prefixed by the
/// relation: they are columns the query reads like any other, and a mirror
/// that never populated them answers the same empty page.
Set<String> filterFieldPaths(FilterNode? filter) {
  final paths = <String>{};

  void walk(FilterNode? node, String prefix) {
    switch (node) {
      case null:
        return;
      case FilterRule(:final field, :final operator, :final value):
        if (operator == 'any' || operator == 'not any') {
          paths.add('$prefix$field');
          walk(parseFilter(value), '$prefix$field.');

          return;
        }

        paths.add('$prefix$field');
      case FilterCondition(:final rules):
        for (final rule in rules) {
          walk(rule, prefix);
        }
    }
  }

  walk(filter, '');

  return paths;
}

/// Field paths an `order_by` reads, stripped of their direction.
Set<String> orderByFieldPaths(dynamic orderBy) {
  final entries = switch (orderBy) {
    null => const <dynamic>[],
    final List<dynamic> list => list,
    final String single => [single],
    _ => const <dynamic>[],
  };

  return {
    for (final entry in entries)
      if (entry is String && entry.isNotEmpty)
        entry.split(':').first.replaceFirst('-', '').trim()
      else if (entry is List && entry.isNotEmpty && entry.first is String)
        (entry.first as String).trim(),
  }..removeWhere((path) => path.isEmpty);
}

/// Resolves a query field path to the column it reads, following one relation
/// hop; null when the path names no stored column (a to-many leaf, an unknown
/// field, a deeper path).
({String model, String column})? resolveQueryColumn(
  LocalSchema schema,
  String model,
  String path,
) {
  final segments = path.split('.');
  final current = schema.models[model];

  if (current == null) {
    return null;
  }

  if (segments.length == 1) {
    final field = current.fields[segments.first];

    return field != null && field.isColumn
        ? (model: model, column: field.name)
        : null;
  }

  if (segments.length != 2) {
    return null;
  }

  final relation = current.fields[segments.first];
  final target = relation?.target;

  if (relation == null ||
      target == null ||
      relation.relationKind == LocalRelationKind.none) {
    return null;
  }

  final leaf = schema.models[target]?.fields[segments.last];

  return leaf != null && leaf.isColumn
      ? (model: target, column: leaf.name)
      : null;
}
