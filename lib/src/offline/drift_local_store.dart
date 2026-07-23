/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:drift/drift.dart';

import 'local_store.dart';
import 'offline_database.dart';

/// [LocalStore] backed by drift/SQLite (native file on io platforms, wasm on
/// the web).
///
/// Records live in a single generic `_records` table (namespace, id, JSON
/// payload) — schema-less at the storage level, no migrations needed.
class DriftLocalStore implements LocalStore {
  final String dbName;
  final OfflineDatabase Function() _databaseOpener;
  OfflineDatabase? _db;

  /// Create a store persisted in [dbName].
  ///
  /// [databaseOpener] overrides the platform database (e.g. an in-memory
  /// drift database in tests).
  DriftLocalStore({
    String dbName = 'data.db',
    OfflineDatabase Function()? databaseOpener,
  }) : dbName = dbName,
       _databaseOpener = databaseOpener ?? (() => OfflineDatabase.open(dbName));

  OfflineDatabase get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalStore is not open (call open() first)');
    }
    return db;
  }

  @override
  Future<void> open() async {
    if (_db != null) {
      return;
    }

    final db = _databaseOpener();
    await renameTableIfNeeded(db, 'records', '_records');
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS _records ('
      'namespace TEXT NOT NULL, '
      'id TEXT NOT NULL, '
      'data TEXT NOT NULL, '
      'PRIMARY KEY (namespace, id))',
    );
    _db = db;
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<Map<String, dynamic>?> get(String model, Object id) async {
    final rows = await _database
        .customSelect(
          'SELECT data FROM _records WHERE namespace = ? AND id = ?',
          variables: [Variable<String>(model), Variable<String>(id.toString())],
        )
        .get();

    return rows.isEmpty ? null : _decode(rows.single.read<String>('data'));
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String model) async {
    final rows = await _database
        .customSelect(
          'SELECT data FROM _records WHERE namespace = ?',
          variables: [Variable<String>(model)],
        )
        .get();

    return rows.map((row) => _decode(row.read<String>('data'))).toList();
  }

  @override
  Future<void> put(String model, Object id, Map<String, dynamic> record) {
    return _database.customStatement(
      'INSERT OR REPLACE INTO _records (namespace, id, data) VALUES (?, ?, ?)',
      [model, id.toString(), jsonEncode(record)],
    );
  }

  @override
  Future<void> putAll(String model, Map<String, Map<String, dynamic>> records) {
    return _database.transaction(() async {
      for (final entry in records.entries) {
        await put(model, entry.key, entry.value);
      }
    });
  }

  @override
  Future<void> replaceAll(
    String model,
    Map<String, Map<String, dynamic>> records,
  ) {
    return _database.transaction(() async {
      await clear(model);

      for (final entry in records.entries) {
        await put(model, entry.key, entry.value);
      }
    });
  }

  @override
  Future<void> delete(String model, Object id) {
    return _database.customStatement(
      'DELETE FROM _records WHERE namespace = ? AND id = ?',
      [model, id.toString()],
    );
  }

  @override
  Future<void> clear(String model) {
    return _database.customStatement(
      'DELETE FROM _records WHERE namespace = ?',
      [model],
    );
  }

  @override
  Future<void> clearAll() {
    return _database.customStatement('DELETE FROM _records');
  }

  Map<String, dynamic> _decode(String data) =>
      jsonDecode(data) as Map<String, dynamic>;
}
