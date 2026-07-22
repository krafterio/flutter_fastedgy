/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  OfflineDatabase.open(String name) : super(driftDatabase(name: name));

  /// Silence drift's multiple-database warning: the offline layer opens two
  /// databases of this class on purpose (records + images), never sharing an
  /// executor.
  static void allowMultipleInstances() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}
