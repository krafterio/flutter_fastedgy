/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:drift/drift.dart';

import 'local_image_store.dart';
import 'offline_database.dart';

/// [LocalImageStore] backed by drift/SQLite, in a database separate from the
/// record store so image payloads never bloat record reads.
///
/// Variants live in a single `images` table keyed by (path, variant).
class DriftLocalImageStore implements LocalImageStore {
  final String dbName;
  final OfflineDatabase Function() _databaseOpener;
  OfflineDatabase? _db;

  /// Create a store persisted in [dbName].
  ///
  /// [databaseOpener] overrides the platform database (e.g. an in-memory
  /// drift database in tests).
  DriftLocalImageStore({
    String dbName = 'fastedgy_offline_images.db',
    OfflineDatabase Function()? databaseOpener,
  }) : dbName = dbName,
       _databaseOpener = databaseOpener ?? (() => OfflineDatabase.open(dbName));

  OfflineDatabase get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalImageStore is not open (call open() first)');
    }
    return db;
  }

  @override
  Future<void> open() async {
    if (_db != null) {
      return;
    }

    final db = _databaseOpener();
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS images ('
      'path TEXT NOT NULL, '
      'variant TEXT NOT NULL, '
      'bytes BLOB NOT NULL, '
      'width INTEGER, '
      'height INTEGER, '
      'PRIMARY KEY (path, variant))',
    );
    _db = db;
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<Uint8List?> getVariant(String path, String variantKey) async {
    final rows = await _database
        .customSelect(
          'SELECT bytes FROM images WHERE path = ? AND variant = ?',
          variables: [Variable<String>(path), Variable<String>(variantKey)],
        )
        .get();

    return rows.isEmpty ? null : rows.single.read<Uint8List>('bytes');
  }

  @override
  Future<bool> hasVariant(String path, String variantKey) async {
    final rows = await _database
        .customSelect(
          'SELECT 1 AS present FROM images WHERE path = ? AND variant = ?',
          variables: [Variable<String>(path), Variable<String>(variantKey)],
        )
        .get();

    return rows.isNotEmpty;
  }

  @override
  Future<Uint8List?> getBestVariant(String path) async {
    final rows = await _database
        .customSelect(
          'SELECT bytes FROM images WHERE path = ? '
          'ORDER BY (width IS NULL AND height IS NULL) DESC, '
          '(COALESCE(width, height, 0) * COALESCE(height, width, 0)) DESC '
          'LIMIT 1',
          variables: [Variable<String>(path)],
        )
        .get();

    return rows.isEmpty ? null : rows.single.read<Uint8List>('bytes');
  }

  @override
  Future<void> putVariant(
    String path,
    String variantKey,
    Uint8List bytes, {
    int? width,
    int? height,
  }) {
    return _database.customStatement(
      'INSERT OR REPLACE INTO images (path, variant, bytes, width, height) '
      'VALUES (?, ?, ?, ?, ?)',
      [path, variantKey, bytes, width, height],
    );
  }

  @override
  Future<void> removePath(String path) {
    return _database.customStatement('DELETE FROM images WHERE path = ?', [
      path,
    ]);
  }

  @override
  Future<List<String>> paths() async {
    final rows = await _database
        .customSelect('SELECT DISTINCT path FROM images')
        .get();

    return rows.map((row) => row.read<String>('path')).toList();
  }

  @override
  Future<void> clear() {
    return _database.customStatement('DELETE FROM images');
  }
}
