/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

/// Schema-less drift database driven at runtime.
///
/// The offline layer declares no code-generated tables: DDL is executed at
/// runtime (`customStatement`) and rows are read as maps (`customSelect`) —
/// the exact input of `BaseModel(json)`.
///
/// [OfflineDatabase.open] uses the official `drift_flutter` opener: native
/// SQLite file (background isolate, path via path_provider) and wasm on the
/// web (requires `sqlite3.wasm` + `drift_worker.js` in the app's `web/`).
class OfflineDatabase extends GeneratedDatabase {
  OfflineDatabase(super.executor);

  /// Open the platform database [name].
  OfflineDatabase.open(String name)
    : super(
        driftDatabase(
          name: name,
          native: const DriftNativeOptions(setup: applyOfflineDatabasePragmas),
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  /// Silence drift's multiple-database warning: tests open several in-memory
  /// databases of this class (production shares a single one).
  static void allowMultipleInstances() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

/// Pragmas applied to every native connection to the offline database.
///
/// Drift runs the connection on a background isolate and sends this function
/// there, so it must stay top-level and capture nothing.
///
/// `journal_mode = WAL` (persisted in the file) is what makes the database
/// safe to open several times at once: the default rollback journal lets a
/// writer block every reader and tolerates a single writer, which breaks as
/// soon as a second app instance — or a second Flutter engine, each engine
/// opening its own connection — touches the file. `busy_timeout` completes it:
/// sqlite3 installs no busy handler by default, so a lock held elsewhere fails
/// immediately with `database is locked` instead of waiting for its release.
void applyOfflineDatabasePragmas(CommonDatabase db) {
  db.execute('pragma journal_mode = WAL');
  db.execute('pragma busy_timeout = 5000');
}

/// Rename table [from] to [to] when [from] exists and [to] does not — a
/// one-time, idempotent migration (e.g. prefixing the system tables with `_`).
/// Safe to call on every open.
Future<void> renameTableIfNeeded(
  OfflineDatabase db,
  String from,
  String to,
) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?)",
        variables: [Variable<String>(from), Variable<String>(to)],
      )
      .get();
  final names = rows.map((row) => row.read<String>('name')).toSet();

  if (names.contains(from) && !names.contains(to)) {
    await db.customStatement('ALTER TABLE "$from" RENAME TO "$to"');
  }
}
