/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';

import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';

import 'local_image_store.dart';
import 'local_store_database.dart';

/// [LocalImageStore] backed by sembast (blobs in the SQLite file on native
/// platforms, IndexedDB on the web), in a database separate from the record
/// store so image payloads never bloat record reads.
///
/// Each storage path maps to a sembast store holding one record per variant
/// (`{bytes, width, height}`); known paths are tracked in a `_meta` store
/// (sembast has no store enumeration API).
class SembastLocalImageStore implements LocalImageStore {
  static const _metaStoreName = '_meta';
  static const _pathsKey = 'paths';

  final String dbName;
  final Future<Database> Function() _databaseOpener;
  Database? _db;

  /// Create a store persisted in [dbName].
  ///
  /// [databaseOpener] overrides the platform database (e.g. an in-memory
  /// sembast database in tests).
  SembastLocalImageStore({
    this.dbName = 'fastedgy_offline_images.db',
    Future<Database> Function()? databaseOpener,
  }) : _databaseOpener = databaseOpener ?? (() => openOfflineDatabase(dbName));

  StoreRef<String, Map<String, Object?>> _pathStore(String path) =>
      stringMapStoreFactory.store(path);

  StoreRef<String, Object?> get _metaStore =>
      StoreRef<String, Object?>(_metaStoreName);

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalImageStore is not open (call open() first)');
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
  Future<Uint8List?> getVariant(String path, String variantKey) async {
    final record = await _pathStore(path).record(variantKey).get(_database);
    final bytes = record?['bytes'];

    return bytes is Blob ? bytes.bytes : null;
  }

  @override
  Future<bool> hasVariant(String path, String variantKey) {
    return _pathStore(path).record(variantKey).exists(_database);
  }

  @override
  Future<Uint8List?> getBestVariant(String path) async {
    final snapshots = await _pathStore(path).find(_database);

    Map<String, Object?>? best;
    var bestArea = -1;

    for (final snapshot in snapshots) {
      final width = snapshot.value['width'] as int?;
      final height = snapshot.value['height'] as int?;

      if (width == null && height == null) {
        best = snapshot.value;
        break;
      }

      final area = (width ?? height ?? 0) * (height ?? width ?? 0);

      if (area > bestArea) {
        bestArea = area;
        best = snapshot.value;
      }
    }

    final bytes = best?['bytes'];

    return bytes is Blob ? bytes.bytes : null;
  }

  @override
  Future<void> putVariant(
    String path,
    String variantKey,
    Uint8List bytes, {
    int? width,
    int? height,
  }) {
    return _database.transaction((txn) async {
      await _pathStore(path).record(variantKey).put(txn, {
        'bytes': Blob(bytes),
        'width': width,
        'height': height,
      });
      await _trackPath(txn, path);
    });
  }

  @override
  Future<void> removePath(String path) {
    return _database.transaction((txn) async {
      await _pathStore(path).delete(txn);
      final tracked = await _trackedPaths(txn);

      if (tracked.contains(path)) {
        await _metaStore
            .record(_pathsKey)
            .put(txn, tracked.where((p) => p != path).toList());
      }
    });
  }

  @override
  Future<List<String>> paths() => _trackedPaths(_database);

  @override
  Future<void> clear() {
    return _database.transaction((txn) async {
      for (final path in await _trackedPaths(txn)) {
        await _pathStore(path).delete(txn);
      }

      await _metaStore.record(_pathsKey).delete(txn);
    });
  }

  Future<void> _trackPath(DatabaseClient client, String path) async {
    final paths = await _trackedPaths(client);

    if (!paths.contains(path)) {
      await _metaStore.record(_pathsKey).put(client, [...paths, path]);
    }
  }

  Future<List<String>> _trackedPaths(DatabaseClient client) async {
    final value = await _metaStore.record(_pathsKey).get(client);

    return value is List ? value.whereType<String>().toList() : <String>[];
  }
}
