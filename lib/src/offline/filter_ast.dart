/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// AST of the FastEdgy Query Builder filters (X-Filter), mirroring the server
/// structures (`fastedgy/orm/filter/types.py`) and the accepted input forms
/// of its parser (`parser.py`):
///
/// - rule: `["field", "operator"]` or `["field", "operator", value]`
/// - condition: `["&", [rule, ...]]` / `["|", [rule, ...]]`
/// - flat condition: `["&", rule1, rule2, ...]`
/// - bare list of rules: implicit AND
library;

/// Raised when a filter expression cannot be parsed (parity with the server's
/// `InvalidFilterError`, which produces a 422).
class InvalidFilterException implements Exception {
  final String message;

  InvalidFilterException(this.message);

  @override
  String toString() => message;
}

sealed class FilterNode {
  const FilterNode();
}

final class FilterRule extends FilterNode {
  final String field;
  final String operator;
  final dynamic value;

  const FilterRule(this.field, this.operator, [this.value]);
}

final class FilterCondition extends FilterNode {
  /// '&' or '|'.
  final String condition;
  final List<FilterNode> rules;

  const FilterCondition(this.condition, this.rules);
}

bool _isRule(dynamic item) =>
    item is List &&
    item.length >= 2 &&
    item.length <= 3 &&
    item[0] is String &&
    item[1] is String;

bool _isCondition(dynamic item) =>
    item is List &&
    item.length == 2 &&
    item[0] is String &&
    ('&' == item[0] || '|' == item[0]) &&
    item[1] is List;

/// Parse a filter input (decoded X-Filter JSON array) into a normalized
/// [FilterCondition] (single rules are wrapped in an AND, like the server).
///
/// Returns null for null/empty input; throws [InvalidFilterException] on a
/// malformed expression.
FilterCondition? parseFilter(dynamic input) {
  if (input == null) {
    return null;
  }

  if (input is FilterCondition) {
    return input;
  }

  if (input is FilterRule) {
    return FilterCondition('&', [input]);
  }

  if (input is! List || input.isEmpty) {
    return input is List
        ? null
        : throw InvalidFilterException('Invalid filter expression');
  }

  final node = _parseNode(input);

  return switch (node) {
    null => null,
    FilterCondition() => node,
    FilterRule() => FilterCondition('&', [node]),
  };
}

FilterNode? _parseNode(List input) {
  if (input.isEmpty) {
    return null;
  }

  if (_isCondition(input)) {
    return FilterCondition(
      input[0] as String,
      _parseChildren(input[1] as List),
    );
  }

  if (_isRule(input)) {
    return FilterRule(
      input[0] as String,
      input[1] as String,
      input.length == 3 ? input[2] : null,
    );
  }

  // Flat condition: ["&", rule1, rule2, ...]
  if (input.length > 1 && (input[0] == '&' || input[0] == '|')) {
    final rules = _parseChildren(input.sublist(1));

    if (rules.isNotEmpty) {
      return FilterCondition(input[0] as String, rules);
    }
  }

  // Bare list of rules/conditions: implicit AND.
  final items = _parseChildren(input);

  if (items.isNotEmpty) {
    return FilterCondition('&', items);
  }

  throw InvalidFilterException('Invalid filter expression');
}

List<FilterNode> _parseChildren(List children) {
  final nodes = <FilterNode>[];

  for (final child in children) {
    if (child is! List) {
      throw InvalidFilterException('Invalid filter expression');
    }

    final node = _parseNode(child);

    if (node != null) {
      nodes.add(node);
    }
  }

  return nodes;
}
