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
/// columns, indexed m2o id columns) — plus a `data` column holding the full
/// JSON payload (fidelity: extra/computed fields survive untouched) and a
/// `ws_scope` column isolating per-workspace mirrors.
///
/// Migrations are automatic: each model's schema fingerprint is stored, and
/// [ensureModel] diffs the live table against the expected schema — additive
/// changes become `ALTER TABLE ADD COLUMN`, anything else rebuilds the table
/// (a replica can always be resynced from the server; no migration files).
class ReplicaStore {
  static const _metaTable = 'replica_models';

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
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_metaTable ('
      'model TEXT NOT NULL PRIMARY KEY, '
      'fingerprint TEXT NOT NULL)',
    );
    _db = db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Create or auto-migrate the table of [model]; check [ReplicaMigration.needsSync]
  /// to know whether the model must be resynced from the server.
  Future<ReplicaMigration> ensureModel(LocalModelSchema model) async {
    if (!model.fields.containsKey('id')) {
      throw ArgumentError('Model "${model.name}" has no id field');
    }

    final table = _tableName(model.name);
    final expected = _expectedColumns(model);
    final existing = await _tableInfo(table);

    if (existing == null) {
      await _createTable(model, table, expected);
      await _saveFingerprint(model);

      return const ReplicaMigration(created: true);
    }

    if (await _storedFingerprint(model.name) == model.fingerprint) {
      return const ReplicaMigration();
    }

    final removedOrChanged = existing.entries.any(
      (entry) => expected[entry.key] != entry.value,
    );

    if (removedOrChanged) {
      await _database.customStatement('DROP TABLE IF EXISTS "$table"');
      await _createTable(model, table, expected);
      await _saveFingerprint(model);

      return const ReplicaMigration(rebuilt: true);
    }

    for (final entry in expected.entries) {
      if (!existing.containsKey(entry.key)) {
        await _database.customStatement(
          'ALTER TABLE "$table" ADD COLUMN "${entry.key}" ${entry.value}',
        );
      }
    }

    await _createIndexes(model, table);
    await _saveFingerprint(model);

    return const ReplicaMigration();
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
        'DELETE FROM "${_tableName(model.name)}" WHERE ws_scope = ?',
        [scope],
      );

      for (final record in records) {
        await _upsert(model, scope, record);
      }
    });
  }

  /// All records of [model] under [scope] (full JSON payloads).
  Future<List<Map<String, dynamic>>> getAll(String model, String scope) async {
    final rows = await _database
        .customSelect(
          'SELECT data FROM "${_tableName(model)}" WHERE ws_scope = ?',
          variables: [Variable<String>(scope)],
        )
        .get();

    return rows.map((row) => _decode(row.read<String>('data'))).toList();
  }

  /// A record by id under [scope], or null.
  Future<Map<String, dynamic>?> getById(
    String model,
    String scope,
    Object id,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT data FROM "${_tableName(model)}" '
          'WHERE ws_scope = ? AND id = ?',
          variables: [Variable<String>(scope), Variable<String>('$id')],
        )
        .get();

    return rows.isEmpty ? null : _decode(rows.single.read<String>('data'));
  }

  /// Delete a record by id under [scope].
  Future<void> deleteById(String model, String scope, Object id) {
    return _database.customStatement(
      'DELETE FROM "${_tableName(model)}" WHERE ws_scope = ? AND id = ?',
      [scope, '$id'],
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
      records: rows.map((row) => _decode(row.read<String>('data'))).toList(),
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
  Future<void> clearAll() async {
    final rows = await _database
        .customSelect('SELECT model FROM $_metaTable')
        .get();

    await _database.transaction(() async {
      for (final row in rows) {
        await clearModel(row.read<String>('model'));
      }
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
    final names = ['ws_scope', 'data', ...columns.map((c) => '"${c.name}"')];
    final values = <Object?>[
      scope,
      jsonEncode(record),
      ...columns.map((c) => _columnValue(c, record[c.name])),
    ];
    final placeholders = List.filled(names.length, '?').join(', ');

    await _database.customStatement(
      'INSERT OR REPLACE INTO "${_tableName(model.name)}" '
      '(${names.join(', ')}) VALUES ($placeholders)',
      values,
    );
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
      'CREATE TABLE "$table" ($defs, PRIMARY KEY (ws_scope, id))',
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
  }

  Map<String, String> _expectedColumns(LocalModelSchema model) => {
    'ws_scope': 'TEXT',
    'data': 'TEXT',
    for (final field in model.columns) field.name: field.sqlAffinity,
  };

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

  Future<String?> _storedFingerprint(String model) async {
    final rows = await _database
        .customSelect(
          'SELECT fingerprint FROM $_metaTable WHERE model = ?',
          variables: [Variable<String>(model)],
        )
        .get();

    return rows.isEmpty ? null : rows.single.read<String>('fingerprint');
  }

  Future<void> _saveFingerprint(LocalModelSchema model) {
    return _database.customStatement(
      'INSERT OR REPLACE INTO $_metaTable (model, fingerprint) VALUES (?, ?)',
      [model.name, model.fingerprint],
    );
  }

  String _tableName(String model) => 'r_$model';

  Map<String, dynamic> _decode(String data) =>
      jsonDecode(data) as Map<String, dynamic>;
}
