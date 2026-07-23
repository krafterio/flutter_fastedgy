/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_helpers.dart';
import 'filter_ast.dart';
import 'local_schema.dart';
import 'replica_search.dart';

/// A filter/order/pagination query compiled to SQL over the replica tables.
class CompiledReplicaQuery {
  final String sql;
  final String countSql;
  final List<Object?> args;
  final List<Object?> countArgs;

  const CompiledReplicaQuery({
    required this.sql,
    required this.countSql,
    required this.args,
    required this.countArgs,
  });
}

/// Compiles the FastEdgy filter AST (X-Filter) to SQL over the [ReplicaStore]
/// tables, mirroring the server semantics (`fastedgy/orm/filter/builder.py`):
///
/// - pure-m2o paths compile to correlated scalar subqueries — the LEFT JOIN
///   semantics of the server lookups (a broken FK chain yields NULL, so
///   `is empty` also matches records without the relation);
/// - paths through a to-many relation compile to `EXISTS` chains (o2m through
///   the resolved reverse FK); in an AND, rules sharing the same relation
///   path are grouped into a single `EXISTS` (same related row — the
///   server's joined lookups), while OR branches get independent `EXISTS`;
/// - `like`-family case sensitivity matches the server: sensitive variants
///   compile to `GLOB`, insensitive ones to SQLite `LIKE` (ASCII folding);
/// - nested `order_by` follows m2o paths through `LEFT JOIN`s with the
///   PostgreSQL null ordering (ASC → NULLS LAST, DESC → NULLS FIRST);
/// - `search`/`search_fuzzy` on the fulltext field compile to FTS5 MATCH
///   subqueries over the `<table>_fts` index (see `replica_search.dart`);
///   `search_fuzzy` degrades to `search` (no pg_trgm equivalent), and
///   ordering on the fulltext field maps the server's `ts_rank` to a
///   weighted `bm25()` (only meaningful alongside a search rule on the root
///   model — skipped otherwise, like the server's rank extra select);
/// - every table access is confined to its replica scope (`_workspace`).
///
/// Unsupported offline (throws [UnsupportedError]): `match`,
/// vector and spatial operators, filters ending on a to-many field, paths
/// through m2m or generic relations, and o2m hops with an ambiguous reverse
/// FK (declare/replicate the pivot instead).
class ReplicaQueryCompiler {
  final LocalSchema schema;

  ReplicaQueryCompiler(this.schema);

  CompiledReplicaQuery compile({
    required String model,
    required String Function(String model) scopeOf,
    FilterCondition? filter,
    dynamic orderBy,
    int? limit,
    int? offset,
  }) {
    final root = schema.models[model];

    if (root == null) {
      throw ArgumentError('Model "$model" is not part of the local schema');
    }

    final ctx = _Context(schema, scopeOf);
    final filterArgs = <Object?>[];
    final filterSql = filter == null
        ? null
        : _compileCondition(ctx, root, 't0', filter, filterArgs);

    final joinArgs = <Object?>[];
    final tailArgs = <Object?>[];
    final order = _compileOrderBy(ctx, root, orderBy, joinArgs, tailArgs);

    final where =
        't0._workspace = ?${filterSql == null ? '' : ' AND ($filterSql)'}';

    var sql =
        'SELECT t0._raw FROM "${_table(root)}" t0'
        '${order.joins} WHERE $where${order.orderBy}';
    final args = <Object?>[
      ...joinArgs,
      scopeOf(model),
      ...filterArgs,
      ...tailArgs,
    ];

    if (limit != null || offset != null) {
      sql += ' LIMIT ?';
      args.add(limit ?? -1);

      if (offset != null) {
        sql += ' OFFSET ?';
        args.add(offset);
      }
    }

    return CompiledReplicaQuery(
      sql: sql,
      countSql:
          'SELECT COUNT(*) AS total FROM "${_table(root)}" t0 WHERE $where',
      args: args,
      countArgs: [scopeOf(model), ...filterArgs],
    );
  }

  String _compileCondition(
    _Context ctx,
    LocalModelSchema model,
    String alias,
    FilterCondition condition,
    List<Object?> args,
  ) {
    final isAnd = condition.condition == '&';
    final parts = <String>[];

    if (isAnd) {
      final grouped = <String, List<(_Path, FilterRule)>>{};

      for (final node in condition.rules) {
        switch (node) {
          case FilterRule():
            final path = _resolvePath(ctx, model, node.field);

            if (_isSingleValued(path.hops)) {
              parts.add(_scalarPredicate(ctx, alias, path, node, args));
            } else {
              // Group by first hop: rules sharing a path prefix share the
              // same EXISTS chain (the server's joined-lookup semantics).
              grouped.putIfAbsent(path.hops.first.field.name, () => []).add((
                path,
                node,
              ));
            }
          case FilterCondition():
            parts.add('(${_compileCondition(ctx, model, alias, node, args)})');
        }
      }

      for (final group in grouped.values) {
        parts.add(_existsTree(ctx, model.name, alias, group, 0, args));
      }
    } else {
      for (final node in condition.rules) {
        switch (node) {
          case FilterRule():
            final path = _resolvePath(ctx, model, node.field);

            if (_isSingleValued(path.hops)) {
              parts.add(_scalarPredicate(ctx, alias, path, node, args));
            } else {
              parts.add(
                _existsTree(ctx, model.name, alias, [(path, node)], 0, args),
              );
            }
          case FilterCondition():
            parts.add('(${_compileCondition(ctx, model, alias, node, args)})');
        }
      }
    }

    if (parts.isEmpty) {
      return '1 = 1';
    }

    return parts.join(isAnd ? ' AND ' : ' OR ');
  }

  // One EXISTS per shared path segment, predicates attached at their depth —
  // the prefix tree mirrors the ORM's join sharing: two AND rules on
  // `members.role` and `members.user.name` constrain the SAME members row.
  String _existsTree(
    _Context ctx,
    String parentModel,
    String parentAlias,
    List<(_Path, FilterRule)> rules,
    int depth,
    List<Object?> args,
  ) {
    final hop = rules.first.$1.hops[depth];
    final alias = ctx.nextAlias('e');
    var from = '"${_table(hop.target)}" $alias';
    final String link;

    switch (hop.kind) {
      case _HopKind.one2many:
        link = '$alias."${hop.reverseField}" = $parentAlias.id';
      case _HopKind.many2one:
        link = '$parentAlias."${hop.field.name}" = $alias.id';
      case _HopKind.genericOne2many:
        link =
            '$alias."${hop.genericReverse!.referenceIdColumn}" = $parentAlias.id '
            'AND $alias."${hop.genericReverse!.referenceModelColumn}" = ?';
        args.add(hop.sourceModel);
      case _HopKind.many2many:
        final pivot = ctx.nextAlias('p');
        from =
            '"${hop.pivotTable}" $pivot '
            'JOIN "${_table(hop.target)}" $alias '
            'ON $alias.id = $pivot.target_id AND $alias._workspace = ?';
        link = '$pivot.parent_id = $parentAlias.id AND $pivot._workspace = ?';
        args.add(ctx.scopeOf(hop.target.name));
        args.add(ctx.scopeOf(parentModel));
    }

    args.add(ctx.scopeOf(hop.target.name));

    final parts = <String>[];
    final deeper = <String, List<(_Path, FilterRule)>>{};

    for (final entry in rules) {
      final rest = entry.$1.hops.sublist(depth + 1);

      if (_allMany2one(rest)) {
        parts.add(
          _predicate(
            ctx,
            _scalarChain(ctx, alias, rest, entry.$1.leaf, args),
            entry.$1.leaf,
            entry.$2,
            args,
          ),
        );
      } else {
        deeper
            .putIfAbsent(entry.$1.hops[depth + 1].field.name, () => [])
            .add(entry);
      }
    }

    for (final group in deeper.values) {
      parts.add(
        _existsTree(ctx, hop.target.name, alias, group, depth + 1, args),
      );
    }

    return 'EXISTS (SELECT 1 FROM $from '
        'WHERE $link AND $alias._workspace = ? AND ${parts.join(' AND ')})';
  }

  /// Whether the path only traverses single-valued (m2o) hops — compiled as
  /// a correlated scalar subquery chain (LEFT JOIN semantics: a broken chain
  /// yields NULL instead of dropping the row).
  bool _isSingleValued(List<_Hop> hops) => hops.isEmpty || _allMany2one(hops);

  bool _allMany2one(List<_Hop> hops) =>
      hops.every((hop) => hop.kind == _HopKind.many2one);

  String _scalarPredicate(
    _Context ctx,
    String alias,
    _Path path,
    FilterRule rule,
    List<Object?> args,
  ) {
    return _predicate(
      ctx,
      _scalarChain(ctx, alias, path.hops, path.leaf, args),
      path.leaf,
      rule,
      args,
    );
  }

  // Nested correlated scalar subqueries following a m2o chain; the innermost
  // expression is the leaf column, a missing related row yields NULL.
  String _scalarChain(
    _Context ctx,
    String parentAlias,
    List<_Hop> hops,
    LocalFieldSchema leaf,
    List<Object?> args,
  ) {
    if (hops.isEmpty) {
      return '$parentAlias."${leaf.name}"';
    }

    final hop = hops.first;
    final alias = ctx.nextAlias('s');
    final inner = _scalarChain(ctx, alias, hops.sublist(1), leaf, args);

    args.add(ctx.scopeOf(hop.target.name));

    return '(SELECT $inner FROM "${_table(hop.target)}" $alias '
        'WHERE $parentAlias."${hop.field.name}" = $alias.id '
        'AND $alias._workspace = ?)';
  }

  String _predicate(
    _Context ctx,
    String column,
    LocalFieldSchema leaf,
    FilterRule rule,
    List<Object?> args,
  ) {
    if (leaf.type == 'fulltext') {
      return _fulltextPredicate(ctx, column, leaf, rule, args);
    }

    if (rule.operator == 'search' || rule.operator == 'search_fuzzy') {
      throw UnsupportedError(
        'Operator "${rule.operator}" is only supported on the fulltext '
        'search field',
      );
    }

    final value = _coerce(leaf, rule.value);

    switch (rule.operator) {
      case '=':
        if (value == null) {
          return '$column IS NULL';
        }
        args.add(value);
        return '$column = ?';
      case '!=':
        if (value == null) {
          return '$column IS NOT NULL';
        }
        args.add(value);
        return '$column != ?';
      case '<' || '<=' || '>' || '>=':
        args.add(value);
        return '$column ${rule.operator} ?';
      case 'between':
        final range = value as List;
        args.add(_coerce(leaf, range[0]));
        args.add(_coerce(leaf, range[1]));
        return '$column BETWEEN ? AND ?';
      case 'like':
        args.add(_sqlPatternToGlob('$value'));
        return '$column GLOB ?';
      case 'not like':
        args.add(_sqlPatternToGlob('$value'));
        return '$column NOT GLOB ?';
      case 'ilike':
        args.add('$value');
        return '$column LIKE ?';
      case 'not ilike':
        args.add('$value');
        return '$column NOT LIKE ?';
      case 'starts with':
        args.add('${_globEscape('$value')}*');
        return '$column GLOB ?';
      case 'not starts with':
        args.add('${_globEscape('$value')}*');
        return '$column NOT GLOB ?';
      case 'ends with':
        args.add('*${_globEscape('$value')}');
        return '$column GLOB ?';
      case 'not ends with':
        args.add('*${_globEscape('$value')}');
        return '$column NOT GLOB ?';
      case 'contains':
        args.add('*${_globEscape('$value')}*');
        return '$column GLOB ?';
      case 'not contains':
        args.add('*${_globEscape('$value')}*');
        return '$column NOT GLOB ?';
      case 'icontains':
        args.add('%${_likeEscape('$value')}%');
        return "$column LIKE ? ESCAPE '\\'";
      case 'not icontains':
        args.add('%${_likeEscape('$value')}%');
        return "$column NOT LIKE ? ESCAPE '\\'";
      case 'in' || 'not in':
        final values = (value as List)
            .map((item) => _coerce(leaf, item))
            .toList();

        if (values.isEmpty) {
          return rule.operator == 'in' ? '0 = 1' : '1 = 1';
        }

        args.addAll(values);
        final placeholders = List.filled(values.length, '?').join(', ');
        final negate = rule.operator == 'not in' ? 'NOT ' : '';
        return '$column ${negate}IN ($placeholders)';
      case 'is true':
        return '$column = 1';
      case 'is false':
        return '$column = 0';
      case 'is empty':
        return '$column IS NULL';
      case 'is not empty':
        return '$column IS NOT NULL';
      default:
        throw UnsupportedError(
          'Operator "${rule.operator}" is not supported offline',
        );
    }
  }

  /// `search`/`search_fuzzy` on a fulltext pseudo-leaf: [column] resolves to
  /// the rowid of the searchable model's row (root alias, EXISTS alias or
  /// m2o scalar chain), matched against its FTS5 index. `search_fuzzy`
  /// intentionally compiles like `search` (no pg_trgm equivalent offline).
  String _fulltextPredicate(
    _Context ctx,
    String column,
    LocalFieldSchema leaf,
    FilterRule rule,
    List<Object?> args,
  ) {
    if (rule.operator != 'search' && rule.operator != 'search_fuzzy') {
      throw UnsupportedError(
        'Operator "${rule.operator}" is not supported on the fulltext '
        'search field offline',
      );
    }

    final value = rule.value;

    if (value == null || '$value'.trim().isEmpty) {
      return '1 = 1';
    }

    final query = parseFtsSearch('$value');

    if (query.isEmpty) {
      return '1 = 1';
    }

    if (column == 't0."rowid"' && query.positive != null) {
      ctx.rootFtsMatch ??= query.positive;
    }

    final fts = '"${ftsTableName(leaf.target!)}"';
    final parts = <String>[];

    if (query.positive != null) {
      args.add(query.positive);
      parts.add('$column IN (SELECT rowid FROM $fts WHERE $fts MATCH ?)');
    }

    if (query.excluded != null) {
      args.add(query.excluded);
      parts.add('$column NOT IN (SELECT rowid FROM $fts WHERE $fts MATCH ?)');
    }

    return parts.length == 1 ? parts.single : '(${parts.join(' AND ')})';
  }

  Object? _coerce(LocalFieldSchema leaf, dynamic value) {
    if (value == null) {
      return null;
    }

    if (leaf.relationKind == LocalRelationKind.many2one && value is Map) {
      return value['id'];
    }

    if (value is bool) {
      return value ? 1 : 0;
    }

    return value;
  }

  ({String joins, String orderBy}) _compileOrderBy(
    _Context ctx,
    LocalModelSchema root,
    dynamic orderBy,
    List<Object?> args,
    List<Object?> tailArgs,
  ) {
    final encoded = ApiHelpers.encodeOrderBy(orderBy);

    if (encoded.isEmpty) {
      return (joins: '', orderBy: '');
    }

    final joins = StringBuffer();
    final joinAliases = <String, String>{};
    final terms = <String>[];

    for (final term in encoded.split(',')) {
      final parts = term.split(':');
      final fieldPath = parts.first.trim();

      if (fieldPath.isEmpty) {
        continue;
      }

      final descending = parts.length > 1 && parts[1].trim() == 'desc';
      final path = _resolvePath(ctx, root, fieldPath);

      if (path.leaf.type == 'fulltext') {
        if (path.hops.isNotEmpty) {
          throw UnsupportedError(
            'order_by on a related fulltext field is not supported offline',
          );
        }

        // The rank only exists alongside a search rule on the root model —
        // the offline counterpart of the server's ts_rank extra select.
        // ts_rank grows with relevance while bm25 decreases: the direction
        // is inverted.
        final match = ctx.rootFtsMatch;

        if (match == null) {
          continue;
        }

        tailArgs.add(match);
        terms.add(
          '${ftsRankSql(_table(root), 't0')} '
          '${descending ? 'ASC NULLS LAST' : 'DESC NULLS FIRST'}',
        );
        continue;
      }

      var alias = 't0';
      var prefix = '';

      for (final hop in path.hops) {
        if (hop.reverseField != null) {
          throw UnsupportedError(
            'order_by through a to-many relation is not supported offline',
          );
        }

        prefix = prefix.isEmpty ? hop.field.name : '$prefix.${hop.field.name}';
        final existing = joinAliases[prefix];

        if (existing == null) {
          final joinAlias = ctx.nextAlias('j');
          joins.write(
            ' LEFT JOIN "${_table(hop.target)}" $joinAlias '
            'ON $alias."${hop.field.name}" = $joinAlias.id '
            'AND $joinAlias._workspace = ?',
          );
          args.add(ctx.scopeOf(hop.target.name));
          joinAliases[prefix] = joinAlias;
          alias = joinAlias;
        } else {
          alias = existing;
        }
      }

      // Approximate the server's locale-aware text ordering (PostgreSQL
      // collation) — SQLite's BINARY default would sort all uppercase first.
      final collate = _isTextualSort(path.leaf) ? ' COLLATE NOCASE' : '';

      terms.add(
        '$alias."${path.leaf.name}"$collate '
        '${descending ? 'DESC NULLS FIRST' : 'ASC NULLS LAST'}',
      );
    }

    return (
      joins: joins.toString(),
      orderBy: terms.isEmpty ? '' : ' ORDER BY ${terms.join(', ')}',
    );
  }

  bool _isTextualSort(LocalFieldSchema leaf) => switch (leaf.type) {
    'datetime' || 'date' || 'json' => false,
    _ =>
      leaf.relationKind == LocalRelationKind.none && leaf.sqlAffinity == 'TEXT',
  };

  _Path _resolvePath(_Context ctx, LocalModelSchema root, String fieldPath) {
    final segments = fieldPath.split('.');
    final hops = <_Hop>[];
    var current = root;

    for (var i = 0; i < segments.length; i++) {
      final field = current.fields[segments[i]];

      if (field == null) {
        // The fulltext field never appears in the metadata fields: it
        // resolves to a pseudo-leaf matched through the FTS5 index of its
        // owner model (carried by `target`), addressed by rowid.
        if (i == segments.length - 1 &&
            current.searchable &&
            segments[i] == current.searchField) {
          return _Path(
            hops: hops,
            leaf: LocalFieldSchema(
              name: 'rowid',
              type: 'fulltext',
              target: current.name,
            ),
          );
        }

        throw InvalidFilterException(
          'Unknown field "${segments[i]}" on model "${current.name}"',
        );
      }

      if (field.relationKind == LocalRelationKind.reference &&
          i == segments.length - 2 &&
          (segments[i + 1] == r'$model' || segments[i + 1] == 'id')) {
        // Virtual pair path on a generic reference: <field>.$model / <field>.id
        // map to the persisted pair columns.
        final isModel = segments[i + 1] == r'$model';

        return _Path(
          hops: hops,
          leaf: LocalFieldSchema(
            name: isModel
                ? field.referenceModelColumn
                : field.referenceIdColumn,
            type: isModel ? 'char' : 'integer',
          ),
        );
      }

      if (i == segments.length - 1) {
        // The fulltext field carries no data (excluded from API payloads):
        // it resolves to a pseudo-leaf matched through the FTS5 index of its
        // owner model (carried by `target`), addressed by rowid.
        if (field.type == 'fulltext') {
          if (!current.searchable) {
            throw UnsupportedError(
              'Model "${current.name}" has no searchable source fields '
              '(path "$fieldPath")',
            );
          }

          return _Path(
            hops: hops,
            leaf: LocalFieldSchema(
              name: 'rowid',
              type: 'fulltext',
              target: current.name,
            ),
          );
        }

        if (!field.isColumn) {
          throw UnsupportedError(
            'Filtering on the to-many field "$fieldPath" is not supported '
            'offline',
          );
        }

        return _Path(hops: hops, leaf: field);
      }

      hops.add(_hop(ctx, current, field, fieldPath));
      current = hops.last.target;
    }

    throw InvalidFilterException('Invalid field path "$fieldPath"');
  }

  _Hop _hop(
    _Context ctx,
    LocalModelSchema model,
    LocalFieldSchema field,
    String fieldPath,
  ) {
    final target = ctx.schema.models[field.target];

    if (target == null) {
      throw UnsupportedError(
        'Model "${field.target}" (path "$fieldPath") is not replicated',
      );
    }

    switch (field.relationKind) {
      case LocalRelationKind.many2one:
        return _Hop(kind: _HopKind.many2one, field: field, target: target);
      case LocalRelationKind.one2many:
        final reverse = ctx.schema.resolveReverseField(model.name, field.name);

        if (reverse != null) {
          return _Hop(
            kind: _HopKind.one2many,
            field: field,
            target: target,
            reverseField: reverse,
          );
        }

        final genericReverse = ctx.schema.resolveGenericReverse(
          model.name,
          field.name,
        );

        if (genericReverse != null) {
          return _Hop(
            kind: _HopKind.genericOne2many,
            field: field,
            target: target,
            genericReverse: genericReverse,
            sourceModel: model.name,
          );
        }

        throw UnsupportedError(
          'The reverse FK of "${model.name}.${field.name}" is ambiguous or '
          'unknown (path "$fieldPath")',
        );
      case LocalRelationKind.many2many:
        return _Hop(
          kind: _HopKind.many2many,
          field: field,
          target: target,
          pivotTable: '${model.name}__${field.name}',
        );
      case LocalRelationKind.reference:
        throw UnsupportedError(
          'Paths through the forward reference "${model.name}.${field.name}" '
          'are not supported offline (path "$fieldPath")',
        );
      case LocalRelationKind.none:
        throw InvalidFilterException(
          '"${model.name}.${field.name}" is not a relation (path "$fieldPath")',
        );
    }
  }

  String _table(LocalModelSchema model) => model.name;

  String _globEscape(String value) => value
      .replaceAll('[', '[[]')
      .replaceAll('*', '[*]')
      .replaceAll('?', '[?]');

  String _sqlPatternToGlob(String pattern) =>
      _globEscape(pattern).replaceAll('%', '*').replaceAll('_', '?');

  String _likeEscape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

class _Context {
  final LocalSchema schema;
  final String Function(String model) scopeOf;
  var _counter = 0;

  /// Positive FTS5 MATCH expression of the first search rule on the root
  /// model — reused by the bm25 rank when ordering on the fulltext field.
  String? rootFtsMatch;

  _Context(this.schema, this.scopeOf);

  String nextAlias(String prefix) => '$prefix${_counter++}';
}

enum _HopKind { many2one, one2many, many2many, genericOne2many }

class _Hop {
  final _HopKind kind;
  final LocalFieldSchema field;
  final LocalModelSchema target;

  /// FK column on [target] pointing back (o2m hop).
  final String? reverseField;

  /// Reference field on [target] pointing back (generic o2m hop).
  final LocalFieldSchema? genericReverse;

  /// Model name stored in the reference pair (generic o2m hop).
  final String? sourceModel;

  /// Pivot table of the m2m hop.
  final String? pivotTable;

  const _Hop({
    required this.kind,
    required this.field,
    required this.target,
    this.reverseField,
    this.genericReverse,
    this.sourceModel,
    this.pivotTable,
  });
}

class _Path {
  final List<_Hop> hops;
  final LocalFieldSchema leaf;

  const _Path({required this.hops, required this.leaf});
}
