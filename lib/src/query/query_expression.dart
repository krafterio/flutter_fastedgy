/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How many values an operator takes: none, one, two (a range), a list, or a
/// sub-filter on the related model.
enum Arity { none, one, two, list, sub }

const _joints = ['&', '|'];

const _arities = {
  'is empty': Arity.none,
  'is not empty': Arity.none,
  'is true': Arity.none,
  'is false': Arity.none,
  'between': Arity.two,
  'in': Arity.list,
  'not in': Arity.list,
  'any': Arity.sub,
  'not any': Arity.sub,
};

var _lastId = 0;

/// How many values [operator] takes.
Arity arityOf(String operator) => _arities[operator] ?? Arity.one;

/// A node of the tree a query builder edits, changed in place as it edits it.
sealed class QueryNode {
  QueryNode() : id = ++_lastId;

  /// Unique across every tree, which lets an editor name a node by it.
  final int id;
}

/// Its children, all of them (`&`) or any of them (`|`).
class QueryGroup extends QueryNode {
  QueryGroup([this.joint = '&', List<QueryNode>? children])
    : children = children ?? [];

  String joint;
  final List<QueryNode> children;
}

/// One condition, `[field, operator, value]`.
class QueryRule extends QueryNode {
  QueryRule([this.field = '', this.operator = '', this.value]);

  String field;
  String operator;

  /// A number, a text, a boolean, a list, or a `[model, id]` pair.
  Object? value;

  /// How the editor shows the rule, never written: `on` for a datetime range
  /// picked as one day.
  String? ui;
}

/// Conditions one and the same related record satisfies,
/// `[field, 'any', filter]`, or that none satisfies (`not any`).
class QueryAnyBlock extends QueryNode {
  QueryAnyBlock(this.field, {this.negated = false, QueryGroup? group})
    : group = group ?? QueryGroup();

  String field;
  bool negated;
  QueryGroup group;
}

/// What the editor does not read, written back as it came.
class QueryOpaque extends QueryNode {
  QueryOpaque(this.raw);

  final Object? raw;
}

bool _isList(Object? item) => item is List;

QueryGroup _asGroup(QueryNode node) =>
    node is QueryGroup ? node : QueryGroup('&', [node]);

QueryNode _readNode(Object? item) {
  if (item is List) {
    final head = item.firstOrNull;

    // `['|', [r1, r2]]`: the joint and the list of its items. `['|', r1]`, a
    // joint and a single rule, is the flat form of one item.
    if (item.length == 2 &&
        _joints.contains(head) &&
        item[1] is List &&
        (item[1] as List).every(_isList)) {
      return QueryGroup(head as String, [
        for (final one in item[1] as List) _readNode(one),
      ]);
    }

    if (item.length > 1 &&
        _joints.contains(head) &&
        item.skip(1).every(_isList)) {
      return QueryGroup(head as String, [
        for (final one in item.skip(1)) _readNode(one),
      ]);
    }

    if ((item.length == 2 || item.length == 3) &&
        head is String &&
        item[1] is String) {
      final operator = item[1] as String;

      if (arityOf(operator) == Arity.sub) {
        final sub = item.length == 3 && item[2] != null
            ? _asGroup(_readNode(item[2]))
            : QueryGroup();

        return QueryAnyBlock(head, negated: operator == 'not any', group: sub);
      }

      return QueryRule(head, operator, item.length == 3 ? item[2] : null);
    }

    if (item.isNotEmpty && item.every(_isList)) {
      return QueryGroup('&', [for (final one in item) _readNode(one)]);
    }
  }

  return QueryOpaque(item);
}

/// Reads an `X-Filter` expression into the tree the query builder edits.
///
/// Every form the server accepts reads: a rule, a group, the flat form
/// `['|', r1, r2]`, a list (all of them), a block on a relation. The root is
/// always a group, empty for `null` or `[]`.
QueryGroup parseExpression(Object? expression) {
  if (expression == null || (expression is List && expression.isEmpty)) {
    return QueryGroup();
  }

  return _asGroup(_readNode(expression));
}

bool _isBlank(Object? value) =>
    value == null || value == '' || (value is num && value.isNaN);

Object? _keyOf(Object? value) => value is Map ? value['id'] : value;

List<Object?>? _writeRule(QueryRule rule) {
  if (rule.field.isEmpty || rule.operator.isEmpty) {
    return null;
  }

  final value = rule.value;

  switch (arityOf(rule.operator)) {
    case Arity.none:
      return [rule.field, rule.operator];
    case Arity.list:
      final values = [
        for (final one in value is List ? value : [value])
          if (!_isBlank(_keyOf(one))) _keyOf(one),
      ];

      return values.isEmpty ? null : [rule.field, rule.operator, values];
    case Arity.two:
      final range = value is List ? value.map(_keyOf).toList() : const [];

      return range.length == 2 && !range.any(_isBlank)
          ? [rule.field, rule.operator, range]
          : null;
    case Arity.one || Arity.sub:
      final key = _keyOf(value);

      return _isBlank(key) ? null : [rule.field, rule.operator, key];
  }
}

Object? _writeGroup(QueryGroup group) {
  final items = [for (final child in group.children) ?_writeNode(child)];

  if (items.isEmpty) {
    return null;
  }

  return items.length == 1 ? items.single : [group.joint, items];
}

Object? _writeNode(QueryNode node) => switch (node) {
  QueryGroup() => _writeGroup(node),
  QueryRule() => _writeRule(node),
  QueryAnyBlock(:final field) =>
    field.isEmpty
        ? null
        : [field, node.negated ? 'not any' : 'any', _writeGroup(node.group)],
  QueryOpaque(:final raw) => raw,
};

/// Writes the tree back as an `X-Filter` expression, or `null` when nothing
/// filters. An incomplete rule is left out, a group of one item is that item,
/// and the only form written is `[joint, [items]]`.
Object? serializeExpression(QueryGroup? tree) =>
    tree == null ? null : _writeGroup(tree);

int _countNode(QueryNode node) => switch (node) {
  QueryGroup(:final children) => children.fold(
    0,
    (total, child) => total + _countNode(child),
  ),
  QueryRule() => _writeRule(node) == null ? 0 : 1,
  QueryAnyBlock(:final field) => field.isEmpty ? 0 : 1,
  QueryOpaque() => 1,
};

/// The conditions a tree applies: its complete rules and its blocks, a block
/// counting one whatever it holds. A rule written as is, unread, counts too.
int countConditions(QueryGroup? tree) => tree == null ? 0 : _countNode(tree);

bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length).every((index) => _same(a[index], b[index]));
  }

  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  }

  return a == b;
}

/// Whether two expressions say the same, once read and written back. The
/// order of the conditions counts.
bool sameExpression(Object? a, Object? b) => _same(
  serializeExpression(parseExpression(a)),
  serializeExpression(parseExpression(b)),
);

/// The node of [tree] carrying [id], with its parent group: null for the
/// root, and for the group of a block.
({QueryNode node, QueryGroup? parent})? findQueryNode(
  QueryGroup? tree,
  int id,
) {
  ({QueryNode node, QueryGroup? parent})? visit(
    QueryNode node,
    QueryGroup? parent,
  ) {
    if (node.id == id) {
      return (node: node, parent: parent);
    }

    final children = switch (node) {
      QueryGroup(:final children) => children,
      QueryAnyBlock(:final group) => [group],
      _ => const <QueryNode>[],
    };

    for (final child in children) {
      final found = visit(child, node is QueryGroup ? node : null);

      if (found != null) {
        return found;
      }
    }

    return null;
  }

  return tree == null ? null : visit(tree, null);
}

const _keep = Object();

/// The tree of a query builder over an expression held elsewhere, the port of
/// `useQueryExpression`.
///
/// The [source] is an expression, or a [ValueListenable] holding one, which
/// the tree follows: it is read again when the source changes meaning, and
/// not when it comes back saying what the tree just wrote, since rebuilding on
/// its own echo would drop the row being typed, which writes nothing yet. It
/// never writes to its source: whoever owns the source copies [expression]
/// into it.
///
/// A node is changed through these methods, which tell the listeners.
class QueryExpression extends ChangeNotifier {
  QueryExpression([Object? source])
    : _source = source is ValueListenable<Object?> ? source : null {
    final listenable = _source;

    _tree = parseExpression(listenable == null ? source : listenable.value);

    if (listenable != null) {
      _seen = _json(listenable.value);
      listenable.addListener(_follow);
    }
  }

  final ValueListenable<Object?>? _source;
  late QueryGroup _tree;
  String? _seen;

  QueryGroup get tree => _tree;

  /// The tree written as an `X-Filter` expression, or null.
  Object? get expression => serializeExpression(_tree);

  /// How many conditions the tree applies.
  int get count => countConditions(_tree);

  static String _json(Object? value) =>
      jsonEncode(value, toEncodable: (_) => null);

  void _follow() {
    final incoming = _source!.value;
    final seen = _json(incoming);

    if (seen == _seen) {
      return;
    }

    _seen = seen;

    if (!sameExpression(incoming, expression)) {
      _tree = parseExpression(incoming);
      notifyListeners();
    }
  }

  QueryGroup? _groupOf(int id) => switch (findQueryNode(_tree, id)?.node) {
    final QueryGroup group => group,
    _ => null,
  };

  int? _append(int groupId, QueryNode node) {
    final group = _groupOf(groupId);

    if (group == null) {
      return null;
    }

    group.children.add(node);
    notifyListeners();

    return node.id;
  }

  /// Adds a rule to a group, and returns its id, or null with no such group.
  int? addRule(
    int groupId, {
    String field = '',
    String operator = '',
    Object? value,
  }) => _append(groupId, QueryRule(field, operator, value));

  /// Adds a group to a group, and returns its id.
  int? addGroup(int groupId, {String joint = '&'}) =>
      _append(groupId, QueryGroup(joint));

  /// Adds a block on the relation [field] to a group, and returns its id.
  int? addAny(int groupId, String field, {bool negated = false}) =>
      _append(groupId, QueryAnyBlock(field, negated: negated));

  /// Changes a rule, or a block ([field], [negated]): what is left out keeps
  /// its value, and [value] and [ui] take null.
  ///
  /// A new [field] or [operator] clears [ui] unless it is given: a datetime
  /// moving from « on » to « between » no longer reads as one day.
  void update(
    int nodeId, {
    String? field,
    String? operator,
    Object? value = _keep,
    Object? ui = _keep,
    bool? negated,
  }) {
    final node = findQueryNode(_tree, nodeId)?.node;

    switch (node) {
      case QueryRule():
        node.field = field ?? node.field;
        node.operator = operator ?? node.operator;

        if (!identical(value, _keep)) {
          node.value = value;
        }

        if (!identical(ui, _keep)) {
          node.ui = ui as String?;
        } else if (field != null || operator != null) {
          node.ui = null;
        }
      case QueryAnyBlock():
        node.field = field ?? node.field;
        node.negated = negated ?? node.negated;
      default:
        return;
    }

    notifyListeners();
  }

  /// Puts [node] in the place of another, a rule turning into a block or
  /// back.
  void replace(int nodeId, QueryNode node) {
    final found = findQueryNode(_tree, nodeId);
    final parent = found?.parent;

    if (found == null || parent == null) {
      return;
    }

    parent.children[parent.children.indexOf(found.node)] = node;
    notifyListeners();
  }

  void setJoint(int groupId, String joint) {
    final group = _groupOf(groupId);

    if (group == null) {
      return;
    }

    group.joint = joint;
    notifyListeners();
  }

  void remove(int nodeId) {
    final found = findQueryNode(_tree, nodeId);
    final parent = found?.parent;

    if (found == null || parent == null) {
      return;
    }

    parent.children.remove(found.node);
    notifyListeners();
  }

  void clear() {
    _tree = QueryGroup();
    notifyListeners();
  }

  /// Rebuilds the tree from [expression], whatever it says.
  void load(Object? expression) {
    _tree = parseExpression(expression);
    notifyListeners();
  }

  @override
  void dispose() {
    _source?.removeListener(_follow);
    super.dispose();
  }
}
