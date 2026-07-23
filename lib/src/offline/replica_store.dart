/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:drift/drift.dart';

import 'filter_ast.dart';
import 'local_schema.dart';
import 'offline_database.dart';
import 'replica_query.dart';
import 'replica_search.dart';

/// Outcome of [ReplicaStore.ensureModel].
class ReplicaMigration {
  /// The table did not exist and was created.
  final bool created;

  /// The stored schema was incompatible: the table was rebuilt and its local
  /// data dropped — the caller must resync the model from the server.
  final bool rebuilt;

  const ReplicaMigration({this.created = false, this.rebuilt = false});

  /// Whether the model has no usable local data and needs a server sync.
  bool get needsSync => created || rebuilt;
}

/// Normalized local replica of server models on drift/SQLite: one table per
/// model, generated at runtime from the [LocalModelSchema] (typed scalar
/// columns, indexed m2o id columns) — plus a `_raw` column holding the full
/// JSON payload (fidelity: extra/computed fields survive untouched) and a
/// `_workspace` column isolating per-workspace mirrors.
///
/// Migrations are automatic: each model's schema fingerprint is stored, and
/// [ensureModel] diffs the live table against the expected schema — additive
/// changes become `ALTER TABLE ADD COLUMN`, anything else rebuilds the table
/// (a replica can always be resynced from the server; no migration files).
class ReplicaStore {
  static const _metaTable = '_replica_models';

  final String dbName;
  final OfflineDatabase Function() _databaseOpener;
  OfflineDatabase? _db;

  /// Create a store persisted in [dbName].
  ///
  /// [databaseOpener] overrides the platform database (e.g. an in-memory
  /// drift database in tests).
  ReplicaStore({
    String dbName = 'fastedgy_replica.db',
    OfflineDatabase Function()? databaseOpener,
  }) : dbName = dbName,
       _databaseOpener = databaseOpener ?? (() => OfflineDatabase.open(dbName));

  OfflineDatabase get _database {
    final db = _db;
    if (db == null) {
      throw StateError('ReplicaStore is not open (call open() first)');
    }
    return db;
  }

  Future<void> open() async {
    if (_db != null) {
      return;
    }

    final db = _databaseOpener();
    // The internal DELETE of INSERT OR REPLACE only fires the FTS delete
    // triggers under recursive_triggers — without it the index drifts.
    await db.customStatement('PRAGMA recursive_triggers = ON');
    await renameTableIfNeeded(db, 'replica_models', _metaTable);
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_metaTable ('
      'model TEXT NOT NULL PRIMARY KEY, '
      'fingerprint TEXT NOT NULL, '
      'search_config TEXT)',
    );
    final metaColumns = await db
        .customSelect('PRAGMA table_info($_metaTable)')
        .get();

    if (!metaColumns.any(
      (row) => row.read<String>('name') == 'search_config',
    )) {
      await db.customStatement(
        'ALTER TABLE $_metaTable ADD COLUMN search_config TEXT',
      );
    }

    _db = db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Create or auto-migrate the table of [model]; check [ReplicaMigration.needsSync]
  /// to know whether the model must be resynced from the server.
  ///
  /// The physical table is ALWAYS diffed against the expected schema — the
  /// stored fingerprint is never trusted as a proof of health: it only
  /// captures the model's fields, so a table left by an older storage layout
  /// (renamed system columns, old table prefixes) can carry a matching
  /// fingerprint while being unusable. Any drift is repaired here: additive
  /// changes become `ALTER TABLE ADD COLUMN`, anything else rebuilds the
  /// table (a replica can always be resynced from the server; no migration
  /// files).
  ///
  /// Repairs are decided ONLY from this observed state, never from a caught
  /// exception (when a statement throws, neither the connection health nor
  /// the transience of the error is knowable — dropping a table there could
  /// destroy data over a transient failure). A migration interrupted by an
  /// error simply rethrows: the next ensure re-diffs the half-migrated table
  /// and finishes or rebuilds it deterministically.
  Future<ReplicaMigration> ensureModel(LocalModelSchema model) async {
    if (!model.fields.containsKey('id')) {
      throw ArgumentError('Model "${model.name}" has no id field');
    }

    final table = _tableName(model.name);
    final migration = await _ensureTable(model, table);
    await _ensureSearch(model, table, fresh: migration.needsSync);

    return migration;
  }

  Future<ReplicaMigration> _ensureTable(
    LocalModelSchema model,
    String table,
  ) async {
    await renameTableIfNeeded(_database, 'r_$table', table);
    final expected = _expectedColumns(model);
    final existing = await _tableInfo(table);

    if (existing == null) {
      await _createTable(model, table, expected);
      await _ensurePivots(model);
      await _saveFingerprint(model);

      return const ReplicaMigration(created: true);
    }

    final removedOrChanged = existing.entries.any(
      (entry) => expected[entry.key] != entry.value,
    );

    if (removedOrChanged) {
      return _rebuild(model, table, expected);
    }

    for (final entry in expected.entries) {
      if (!existing.containsKey(entry.key)) {
        await _database.customStatement(
          'ALTER TABLE "$table" ADD COLUMN "${entry.key}" ${entry.value}',
        );
      }
    }

    await _createIndexes(model, table);
    await _ensurePivots(model);
    await _saveFingerprint(model);

    return const ReplicaMigration();
  }

  /// Drop and recreate the table of [model] (and its pivots): local data is
  /// lost, the caller must resync from the server.
  Future<ReplicaMigration> _rebuild(
    LocalModelSchema model,
    String table,
    Map<String, String> expected,
  ) async {
    await _database.customStatement('DROP TABLE IF EXISTS "$table"');
    await _dropPivots(model);
    await _createTable(model, table, expected);
    await _ensurePivots(model);
    await _saveFingerprint(model);

    return const ReplicaMigration(rebuilt: true);
  }

  /// Insert or update [records] (full JSON payloads) under [scope].
  Future<void> upsertAll(
    LocalModelSchema model,
    String scope,
    Iterable<Map<String, dynamic>> records,
  ) {
    return _database.transaction(() async {
      for (final record in records) {
        await _upsert(model, scope, record);
      }
    });
  }

  /// Replace the whole [scope] of [model] with [records] (transactional
  /// prune + insert, mirroring a full sync).
  Future<void> replaceScope(
    LocalModelSchema model,
    String scope,
    Iterable<Map<String, dynamic>> records,
  ) {
    return _database.transaction(() async {
      await _database.customStatement(
        'DELETE FROM "${_tableName(model.name)}" WHERE _workspace = ?',
        [scope],
      );

      for (final field in model.manyToMany) {
        await _database.customStatement(
          'DELETE FROM "${pivotTableName(model.name, field.name)}" '
          'WHERE _workspace = ?',
          [scope],
        );
      }

      for (final record in records) {
        await _upsert(model, scope, record);
      }
    });
  }

  /// All records of [model] under [scope] (full JSON payloads).
  Future<List<Map<String, dynamic>>> getAll(String model, String scope) async {
    final rows = await _database
        .customSelect(
          'SELECT _raw FROM "${_tableName(model)}" WHERE _workspace = ?',
          variables: [Variable<String>(scope)],
        )
        .get();

    return rows.map((row) => _decode(row.read<String>('_raw'))).toList();
  }

  /// A record by id under [scope], or null.
  Future<Map<String, dynamic>?> getById(
    String model,
    String scope,
    Object id,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT _raw FROM "${_tableName(model)}" '
          'WHERE _workspace = ? AND id = ?',
          variables: [Variable<String>(scope), Variable<String>('$id')],
        )
        .get();

    return rows.isEmpty ? null : _decode(rows.single.read<String>('_raw'));
  }

  /// Delete a record by id under [scope].
  Future<void> deleteById(String model, String scope, Object id) {
    return _database.customStatement(
      'DELETE FROM "${_tableName(model)}" WHERE _workspace = ? AND id = ?',
      [scope, '$id'],
    );
  }

  /// Local manifest of [model] under [scope]: record id (as string) →
  /// raw `updated_at` (null when the model has no such column).
  Future<Map<String, String?>> manifest(
    LocalModelSchema model,
    String scope,
  ) async {
    final hasUpdatedAt = model.fields.containsKey('updated_at');
    final rows = await _database
        .customSelect(
          'SELECT id${hasUpdatedAt ? ', updated_at' : ''} '
          'FROM "${_tableName(model.name)}" WHERE _workspace = ?',
          variables: [Variable<String>(scope)],
        )
        .get();

    return {
      for (final row in rows)
        '${row.data['id']}': hasUpdatedAt
            ? row.data['updated_at'] as String?
            : null,
    };
  }

  /// Apply a sync delta transactionally: delete [deletedIds] then upsert
  /// [upserts] under [scope].
  Future<void> applyDelta(
    LocalModelSchema model,
    String scope,
    Iterable<Map<String, dynamic>> upserts,
    Iterable<Object> deletedIds,
  ) {
    return _database.transaction(() async {
      for (final id in deletedIds) {
        await _database.customStatement(
          'DELETE FROM "${_tableName(model.name)}" '
          'WHERE _workspace = ? AND id = ?',
          [scope, '$id'],
        );

        for (final field in model.manyToMany) {
          await _database.customStatement(
            'DELETE FROM "${pivotTableName(model.name, field.name)}" '
            'WHERE _workspace = ? AND parent_id = ?',
            [scope, '$id'],
          );
        }
      }

      for (final record in upserts) {
        await _upsert(model, scope, record);
      }
    });
  }

  /// Number of records of [model] under [scope].
  Future<int> countScope(String model, String scope) async {
    final rows = await _database
        .customSelect(
          'SELECT COUNT(*) AS total FROM "${_tableName(model)}" '
          'WHERE _workspace = ?',
          variables: [Variable<String>(scope)],
        )
        .get();

    return rows.single.read<int>('total');
  }

  /// Delete every record of [model] under [scope].
  Future<void> clearScope(String model, String scope) {
    return _database.customStatement(
      'DELETE FROM "${_tableName(model)}" WHERE _workspace = ?',
      [scope],
    );
  }

  /// Evaluate a FastEdgy query (X-Filter array, order_by, pagination) against
  /// the replica of [model] under [scope], with server-parity semantics (see
  /// [ReplicaQueryCompiler]).
  ///
  /// [scopeOf] overrides the scope per related model (e.g. a globally
  /// replicated model traversed from a workspace-scoped one); defaults to
  /// [scope] everywhere.
  Future<({List<Map<String, dynamic>> records, int total})> query(
    LocalSchema schema,
    String model, {
    required String scope,
    String Function(String model)? scopeOf,
    dynamic filter,
    dynamic orderBy,
    int? limit,
    int? offset,
  }) async {
    final compiled = ReplicaQueryCompiler(schema).compile(
      model: model,
      scopeOf: scopeOf ?? (_) => scope,
      filter: parseFilter(filter),
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    final rows = await _database
        .customSelect(
          compiled.sql,
          variables: compiled.args.map(_variable).toList(),
        )
        .get();
    final count = await _database
        .customSelect(
          compiled.countSql,
          variables: compiled.countArgs.map(_variable).toList(),
        )
        .get();

    return (
      records: rows.map((row) => _decode(row.read<String>('_raw'))).toList(),
      total: count.single.read<int>('total'),
    );
  }

  Variable _variable(Object? value) => switch (value) {
    null => const Variable<String>(null),
    final int v => Variable<int>(v),
    final double v => Variable<double>(v),
    final bool v => Variable<bool>(v),
    _ => Variable<String>('$value'),
  };

  /// Delete every record of [model] (all scopes), keeping the table.
  Future<void> clearModel(String model) {
    return _database.customStatement('DELETE FROM "${_tableName(model)}"');
  }

  /// Delete every record of every replicated model (e.g. on logout).
  /// Full reset (logout): drop every replicated model table and its pivots and
  /// forget their fingerprints, so the next sync rebuilds them from scratch.
  Future<void> clearAll() async {
    final models =
        (await _database.customSelect('SELECT model FROM $_metaTable').get())
            .map((row) => row.read<String>('model'))
            .toSet();
    final tables =
        (await _database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table'",
                )
                .get())
            .map((row) => row.read<String>('name'));

    await _database.transaction(() async {
      for (final table in tables) {
        if (models.contains(table) ||
            models.any(
              (model) =>
                  table.startsWith('${model}__') ||
                  table == ftsTableName(model),
            )) {
          await _database.customStatement('DROP TABLE IF EXISTS "$table"');
        }
      }
      await _database.customStatement('DELETE FROM $_metaTable');
    });
  }

  Future<void> _upsert(
    LocalModelSchema model,
    String scope,
    Map<String, dynamic> record,
  ) async {
    if (record['id'] == null) {
      return;
    }

    final columns = model.columns.toList();
    final references = model.references.toList();
    final search = model.searchable
        ? computeSearchValues(model, record)
        : const <String, String>{};
    final names = [
      '_workspace',
      '_raw',
      ...columns.map((c) => '"${c.name}"'),
      for (final field in references) ...[
        '"${field.referenceModelColumn}"',
        '"${field.referenceIdColumn}"',
      ],
      ...search.keys.map((column) => '"$column"'),
    ];
    final values = <Object?>[
      scope,
      jsonEncode(record),
      ...columns.map((c) => _columnValue(c, record[c.name])),
      for (final field in references) ...[
        (record[field.name] as Map?)?[r'$model'],
        (record[field.name] as Map?)?['id'],
      ],
      ...search.values,
    ];
    final placeholders = List.filled(names.length, '?').join(', ');

    await _database.customStatement(
      'INSERT OR REPLACE INTO "${_tableName(model.name)}" '
      '(${names.join(', ')}) VALUES ($placeholders)',
      values,
    );

    for (final field in model.manyToMany) {
      // Only records carrying the m2m key rewrite its pairs: a partial merge
      // (outbox healing) must not clobber the mirrored links.
      if (!record.containsKey(field.name) || record[field.name] is! List) {
        continue;
      }

      final pivot = pivotTableName(model.name, field.name);

      await _database.customStatement(
        'DELETE FROM "$pivot" WHERE _workspace = ? AND parent_id = ?',
        [scope, record['id']],
      );

      for (final item in record[field.name] as List) {
        final targetId = item is Map ? item['id'] : item;

        if (targetId != null) {
          await _database.customStatement(
            'INSERT OR REPLACE INTO "$pivot" '
            '(_workspace, parent_id, target_id) VALUES (?, ?, ?)',
            [scope, record['id'], targetId],
          );
        }
      }
    }
  }

  Object? _columnValue(LocalFieldSchema field, dynamic value) {
    if (value == null) {
      return null;
    }

    if (field.relationKind == LocalRelationKind.many2one) {
      return value is Map ? value['id'] : value;
    }

    if (value is bool) {
      return value ? 1 : 0;
    }

    if (value is Map || value is List) {
      return jsonEncode(value);
    }

    return value;
  }

  Future<void> _createTable(
    LocalModelSchema model,
    String table,
    Map<String, String> columns,
  ) async {
    final defs = columns.entries
        .map((entry) => '"${entry.key}" ${entry.value}')
        .join(', ');

    await _database.customStatement(
      'CREATE TABLE "$table" ($defs, PRIMARY KEY (_workspace, id))',
    );
    await _createIndexes(model, table);
  }

  Future<void> _createIndexes(LocalModelSchema model, String table) async {
    for (final field in model.columns) {
      if (field.relationKind == LocalRelationKind.many2one) {
        await _database.customStatement(
          'CREATE INDEX IF NOT EXISTS "idx_${table}_${field.name}" '
          'ON "$table" ("${field.name}")',
        );
      }
    }

    for (final field in model.references) {
      await _database.customStatement(
        'CREATE INDEX IF NOT EXISTS "idx_${table}_${field.name}_pair" '
        'ON "$table" ("${field.referenceModelColumn}", "${field.referenceIdColumn}")',
      );
    }
  }

  /// Physical schema of every m2m pivot table: the workspace isolation
  /// column and the relation pair. Single source for both the CREATE
  /// statement and the self-repair diff of [_ensurePivots].
  static const _pivotColumns = {
    '_workspace': 'CHAR',
    'parent_id': 'INTEGER',
    'target_id': 'INTEGER',
  };

  Future<void> _ensurePivots(LocalModelSchema model) async {
    for (final field in model.manyToMany) {
      final pivot = pivotTableName(model.name, field.name);
      await renameTableIfNeeded(_database, 'r_$pivot', pivot);
      final existing = await _tableInfo(pivot);

      // Same self-repair as the model tables: a pivot left by an older
      // storage layout is dropped and recreated (its pairs come back with
      // the next sync of the parent model).
      if (existing != null &&
          (existing.length != _pivotColumns.length ||
              existing.entries.any(
                (entry) => _pivotColumns[entry.key] != entry.value,
              ))) {
        await _database.customStatement('DROP TABLE IF EXISTS "$pivot"');
      }

      final defs = _pivotColumns.entries
          .map((entry) => '${entry.key} ${entry.value}')
          .join(', ');

      await _database.customStatement(
        'CREATE TABLE IF NOT EXISTS "$pivot" '
        '($defs, PRIMARY KEY (${_pivotColumns.keys.join(', ')}))',
      );
      await _database.customStatement(
        'CREATE INDEX IF NOT EXISTS "idx_${pivot}_target" '
        'ON "$pivot" (target_id)',
      );
    }
  }

  Future<void> _dropPivots(LocalModelSchema model) async {
    for (final field in model.manyToMany) {
      await _database.customStatement(
        'DROP TABLE IF EXISTS "${pivotTableName(model.name, field.name)}"',
      );
    }
  }

  /// Create or self-repair the fulltext machinery of [model]: the FTS5 index
  /// table, its sync triggers and the derived `search_value_fts_*` columns.
  ///
  /// Same philosophy as [ensureModel], applied to derived data (never a
  /// resync): the physical DDL (fts table + triggers, read back verbatim
  /// from `sqlite_master`) is diffed against the expected one, the stored
  /// search configuration decides a local recompute of the derived columns
  /// from `_raw`, and an FTS5 `integrity-check` (index versus content)
  /// catches drift left by older layouts — any anomaly ends in the same
  /// idempotent repair: recompute if needed, then reindex with `rebuild`.
  ///
  /// [fresh] skips the recompute and the integrity check when the table was
  /// just created or rebuilt (it is empty).
  Future<void> _ensureSearch(
    LocalModelSchema model,
    String table, {
    required bool fresh,
  }) async {
    final fts = ftsTableName(table);
    final existingSql = await _masterSql('table', fts);
    final existingTriggers = await _ftsTriggerInfo(table);

    if (!model.searchable) {
      for (final name in existingTriggers.keys) {
        await _database.customStatement('DROP TRIGGER IF EXISTS "$name"');
      }

      if (existingSql != null) {
        await _database.customStatement('DROP TABLE IF EXISTS "$fts"');
      }

      await _saveSearchConfig(model.name, null);
      return;
    }

    final expectedSql = ftsCreateSql(table);
    final expectedTriggers = ftsTriggerSqls(table);
    final structureOk =
        existingSql == expectedSql &&
        existingTriggers.length == expectedTriggers.length &&
        expectedTriggers.entries.every(
          (entry) => existingTriggers[entry.key] == entry.value,
        );
    final configOk =
        await _loadSearchConfig(model.name) == model.searchFingerprint;

    if (structureOk && configOk) {
      if (fresh) {
        return;
      }

      try {
        await _database.customStatement(
          'INSERT INTO "$fts"("$fts", rank) VALUES (\'integrity-check\', 1)',
        );
        return;
      } catch (_) {
        // The check IS the observation: it only throws when the index does
        // not match the content (or on a pre-3.42 SQLite, where the harmless
        // fallback is to reindex). Repairing here never destroys data — the
        // whole index derives from columns that stay in place.
      }
    }

    for (final name in existingTriggers.keys) {
      await _database.customStatement('DROP TRIGGER IF EXISTS "$name"');
    }

    if (existingSql != null) {
      await _database.customStatement('DROP TABLE IF EXISTS "$fts"');
    }

    if (!configOk && !fresh) {
      await _recomputeSearchColumns(model, table);
    }

    await _database.customStatement(expectedSql);

    for (final sql in expectedTriggers.values) {
      await _database.customStatement(sql);
    }

    await _database.customStatement(
      'INSERT INTO "$fts"("$fts") VALUES (\'rebuild\')',
    );
    await _saveSearchConfig(model.name, model.searchFingerprint);
  }

  /// Recompute the derived search columns of every row from its `_raw`
  /// payload — the local, lossless repair when the search configuration
  /// changed. Only called with the FTS triggers dropped.
  Future<void> _recomputeSearchColumns(
    LocalModelSchema model,
    String table,
  ) async {
    final rows = await _database
        .customSelect('SELECT rowid AS rid, _raw FROM "$table"')
        .get();

    await _database.transaction(() async {
      for (final row in rows) {
        final values = computeSearchValues(
          model,
          _decode(row.read<String>('_raw')),
        );

        await _database.customStatement(
          'UPDATE "$table" SET '
          '${values.keys.map((column) => '"$column" = ?').join(', ')} '
          'WHERE rowid = ?',
          [...values.values, row.read<int>('rid')],
        );
      }
    });
  }

  Future<String?> _masterSql(String type, String name) async {
    final rows = await _database
        .customSelect(
          'SELECT sql FROM sqlite_master WHERE type = ? AND name = ?',
          variables: [Variable<String>(type), Variable<String>(name)],
        )
        .get();

    return rows.isEmpty ? null : rows.single.read<String?>('sql');
  }

  /// The FTS sync triggers existing on [table], name → verbatim DDL.
  Future<Map<String, String>> _ftsTriggerInfo(String table) async {
    final rows = await _database
        .customSelect(
          'SELECT name, sql FROM sqlite_master '
          "WHERE type = 'trigger' AND tbl_name = ?",
          variables: [Variable<String>(table)],
        )
        .get();
    final prefix = '${ftsTableName(table)}_';

    return {
      for (final row in rows)
        if (row.read<String>('name').startsWith(prefix))
          row.read<String>('name'): row.read<String?>('sql') ?? '',
    };
  }

  Future<String?> _loadSearchConfig(String model) async {
    final rows = await _database
        .customSelect(
          'SELECT search_config FROM $_metaTable WHERE model = ?',
          variables: [Variable<String>(model)],
        )
        .get();

    return rows.isEmpty ? null : rows.single.read<String?>('search_config');
  }

  Future<void> _saveSearchConfig(String model, String? config) {
    return _database.customStatement(
      'UPDATE $_metaTable SET search_config = ? WHERE model = ?',
      [config, model],
    );
  }

  Map<String, String> _expectedColumns(LocalModelSchema model) => {
    '_workspace': 'CHAR',
    '_raw': 'JSON',
    for (final field in model.columns) field.name: field.sqlAffinity,
    for (final field in model.references) ...{
      field.referenceModelColumn: 'TEXT',
      field.referenceIdColumn: 'INTEGER',
    },
    if (model.searchable)
      for (final column in searchColumns) column: 'TEXT',
  };

  /// Pivot table persisting the pairs of a direct m2m [field] of [model].
  String pivotTableName(String model, String field) => '${model}__$field';

  Future<Map<String, String>?> _tableInfo(String table) async {
    final rows = await _database
        .customSelect('PRAGMA table_info("$table")')
        .get();

    if (rows.isEmpty) {
      return null;
    }

    return {
      for (final row in rows)
        row.read<String>('name'): row.read<String>('type'),
    };
  }

  // The fingerprint is stored for diagnostics only ([_metaTable] is also the
  // model registry [clearAll] relies on); table health is always established
  // by diffing the physical columns, never by reading it back.
  Future<void> _saveFingerprint(LocalModelSchema model) {
    return _database.customStatement(
      'INSERT INTO $_metaTable (model, fingerprint) VALUES (?, ?) '
      'ON CONFLICT(model) DO UPDATE SET fingerprint = excluded.fingerprint',
      [model.name, model.fingerprint],
    );
  }

  String _tableName(String model) => model;

  Map<String, dynamic> _decode(String data) =>
      jsonDecode(data) as Map<String, dynamic>;
}
