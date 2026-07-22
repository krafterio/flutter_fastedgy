/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:sembast/sembast.dart';

import 'local_store.dart';
import 'local_store_database.dart';

/// [LocalStore] backed by sembast: SQLite file on native platforms (sqflite),
/// IndexedDB on the web.
///
/// Each model namespace maps to a sembast store; records are stored as
/// JSON-encodable maps keyed by the record id as string. Known namespaces are
/// tracked in a `_meta` store so [clearAll] can purge everything (sembast has
/// no store enumeration API).
class SembastLocalStore implements LocalStore {
  static const _metaStoreName = '_meta';
  static const _modelsKey = 'models';

  final String dbName;
  final Future<Database> Function() _databaseOpener;
  Database? _db;

  /// Create a store persisted in [dbName].
  ///
  /// [databaseOpener] overrides the platform database (e.g. an in-memory
  /// sembast database in tests).
  SembastLocalStore({
    this.dbName = 'fastedgy_offline.db',
    Future<Database> Function()? databaseOpener,
  }) : _databaseOpener = databaseOpener ?? (() => openOfflineDatabase(dbName));

  StoreRef<String, Map<String, Object?>> _store(String model) =>
      stringMapStoreFactory.store(model);

  StoreRef<String, Object?> get _metaStore =>
      StoreRef<String, Object?>(_metaStoreName);

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalStore is not open (call open() first)');
    }
    return db;
  }

  @override
  Future<void> open() async {
    _db ??= await _databaseOpener();
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<Map<String, dynamic>?> get(String model, Object id) async {
    final value = await _store(model).record(id.toString()).get(_database);

    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String model) async {
    final snapshots = await _store(model).find(_database);

    return snapshots
        .map((snapshot) => Map<String, dynamic>.from(snapshot.value))
        .toList();
  }

  @override
  Future<void> put(String model, Object id, Map<String, dynamic> record) {
    return _database.transaction((txn) async {
      await _store(model).record(id.toString()).put(txn, record);
      await _trackModel(txn, model);
    });
  }

  @override
  Future<void> putAll(String model, Map<String, Map<String, dynamic>> records) {
    return _database.transaction((txn) async {
      final store = _store(model);

      for (final entry in records.entries) {
        await store.record(entry.key).put(txn, entry.value);
      }

      await _trackModel(txn, model);
    });
  }

  @override
  Future<void> replaceAll(
    String model,
    Map<String, Map<String, dynamic>> records,
  ) {
    return _database.transaction((txn) async {
      final store = _store(model);
      await store.delete(txn);

      for (final entry in records.entries) {
        await store.record(entry.key).put(txn, entry.value);
      }

      await _trackModel(txn, model);
    });
  }

  @override
  Future<void> delete(String model, Object id) {
    return _store(model).record(id.toString()).delete(_database);
  }

  @override
  Future<void> clear(String model) async {
    await _store(model).delete(_database);
  }

  @override
  Future<void> clearAll() {
    return _database.transaction((txn) async {
      for (final model in await _trackedModels(txn)) {
        await _store(model).delete(txn);
      }

      await _metaStore.record(_modelsKey).delete(txn);
    });
  }

  Future<void> _trackModel(DatabaseClient client, String model) async {
    final models = await _trackedModels(client);

    if (!models.contains(model)) {
      await _metaStore.record(_modelsKey).put(client, [...models, model]);
    }
  }

  Future<List<String>> _trackedModels(DatabaseClient client) async {
    final value = await _metaStore.record(_modelsKey).get(client);

    return value is List ? value.whereType<String>().toList() : <String>[];
  }
}
