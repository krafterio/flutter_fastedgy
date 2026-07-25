/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:drift/drift.dart';

import 'offline_database.dart';

/// Monotonic counters persisted in the offline database (`_sequence` table).
///
/// Two families of counters, one row each:
/// - `temp_id:<model>` — the negative id an optimistic offline create gets
///   until the replay assigns the server one (-1, -2, -3…);
/// - `ph:<model>:<field>` — the number interpolated into a field's
///   `local_placeholder` template (1, 2, 3…), so the first records created
///   offline read `DRAFT-1`, `DRAFT-2`…
///
/// Allocation is a single `INSERT … ON CONFLICT … RETURNING` statement rather
/// than a read-then-write: several app instances share the database file, and
/// two of them reading the same value before either writes would hand out the
/// same id twice.
class LocalSequence {
  static const _table = '_sequence';

  final String dbName;
  final OfflineDatabase Function() _databaseOpener;
  OfflineDatabase? _db;

  /// Create counters persisted in [dbName].
  ///
  /// [databaseOpener] overrides the platform database (e.g. an in-memory drift
  /// database in tests, or the shared one in production).
  LocalSequence({
    this.dbName = 'data.db',
    OfflineDatabase Function()? databaseOpener,
  }) : _databaseOpener = databaseOpener ?? (() => OfflineDatabase.open(dbName));

  OfflineDatabase get _database {
    final db = _db;

    if (db == null) {
      throw StateError('LocalSequence is not open (call open() first)');
    }

    return db;
  }

  /// Open the underlying database (idempotent).
  Future<void> open() async {
    if (_db != null) {
      return;
    }

    final db = _databaseOpener();
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_table ('
      'name TEXT NOT NULL PRIMARY KEY, '
      'value INTEGER NOT NULL)',
    );
    _db = db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// The next temporary id for [model] (-1, then -2, …).
  ///
  /// Scoped per model, so two models hand out the same values: the replay
  /// resolves a temporary id through the model it belongs to, never by value
  /// alone.
  Future<int> nextTempId(String model) => _next('temp_id:$model', -1);

  /// The next placeholder counter for [model].[field] (1, then 2, …).
  Future<int> nextPlaceholder(String model, String field) =>
      _next('ph:$model:$field', 1);

  /// The current value of a counter without allocating, or null when it never
  /// allocated.
  Future<int?> peek(String name) async {
    final rows = await _database
        .customSelect(
          'SELECT value FROM $_table WHERE name = ?',
          variables: [Variable<String>(name)],
        )
        .get();

    return rows.isEmpty ? null : rows.single.read<int>('value');
  }

  /// Reset every counter (logout: the temporary ids they numbered are gone
  /// with the rest of the cache).
  Future<void> clearAll() => _database.customStatement('DELETE FROM $_table');

  Future<int> _next(String name, int step) async {
    final rows = await _database
        .customSelect(
          'INSERT INTO $_table (name, value) VALUES (?, ?) '
          'ON CONFLICT(name) DO UPDATE SET value = value + ? '
          'RETURNING value',
          variables: [
            Variable<String>(name),
            Variable<int>(step),
            Variable<int>(step),
          ],
        )
        .get();

    return rows.single.read<int>('value');
  }
}
