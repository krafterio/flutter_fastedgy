/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_image_store.dart';
import 'offline_database.dart';

/// [LocalImageStore] that keeps the image **bytes on the filesystem** and only
/// an index row per variant in the database (path, variant, file, width,
/// height) — no BLOB. This keeps the SQLite file small so it can be merged
/// with the other offline data.
///
/// Files live in an `fastedgy_offline_images/` directory under the app support
/// directory; each variant maps to a deterministic file name, so re-storing a
/// variant overwrites its file. A missing file (deleted out of band) resolves
/// to null like an absent variant.
class FilesystemLocalImageStore implements LocalImageStore {
  static const _table = 'image_files';

  final String dbName;
  final OfflineDatabase Function() _databaseOpener;
  final Future<Directory> Function() _directoryOpener;
  OfflineDatabase? _db;
  Directory? _dir;

  /// Create a store whose index lives in [dbName] and whose bytes live under
  /// [directoryOpener] (defaults to the app support directory).
  ///
  /// [databaseOpener] and [directoryOpener] are test seams (in-memory drift
  /// database, temporary directory).
  FilesystemLocalImageStore({
    String dbName = 'fastedgy_offline_images.db',
    OfflineDatabase Function()? databaseOpener,
    Future<Directory> Function()? directoryOpener,
  }) : dbName = dbName,
       _databaseOpener = databaseOpener ?? (() => OfflineDatabase.open(dbName)),
       _directoryOpener = directoryOpener ?? getApplicationSupportDirectory;

  OfflineDatabase get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalImageStore is not open (call open() first)');
    }
    return db;
  }

  Future<Directory> get _directory async {
    final dir = _dir;
    if (dir != null) {
      return dir;
    }

    final base = await _directoryOpener();
    final resolved = Directory(p.join(base.path, 'fastedgy_offline_images'));
    await resolved.create(recursive: true);

    return _dir = resolved;
  }

  File _fileFor(Directory dir, String fileName) =>
      File(p.join(dir.path, fileName));

  /// Deterministic, filesystem-safe file name for a (path, variant) pair.
  String _fileName(String path, String variantKey) {
    // FNV-1a 64-bit over the key: fixed-length, no unsafe characters, stable
    // across runs so the same variant reuses the same file.
    var hash = 0xcbf29ce484222325;
    for (final unit in '$path|$variantKey'.codeUnits) {
      hash = (hash ^ unit) * 0x100000001b3;
      hash &= 0xFFFFFFFFFFFFFFFF;
    }

    return '${hash.toRadixString(16).padLeft(16, '0')}.img';
  }

  @override
  Future<void> open() async {
    if (_db != null) {
      return;
    }

    final db = _databaseOpener();
    // Reclaim the legacy BLOB table: bytes now live on disk.
    await db.customStatement('DROP TABLE IF EXISTS images');
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_table ('
      'path TEXT NOT NULL, '
      'variant TEXT NOT NULL, '
      'file TEXT NOT NULL, '
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

  Future<Uint8List?> _readFile(String fileName) async {
    final file = _fileFor(await _directory, fileName);

    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<Uint8List?> getVariant(String path, String variantKey) async {
    final rows = await _database
        .customSelect(
          'SELECT file FROM $_table WHERE path = ? AND variant = ?',
          variables: [Variable<String>(path), Variable<String>(variantKey)],
        )
        .get();

    return rows.isEmpty ? null : _readFile(rows.single.read<String>('file'));
  }

  @override
  Future<bool> hasVariant(String path, String variantKey) async {
    final rows = await _database
        .customSelect(
          'SELECT 1 AS present FROM $_table WHERE path = ? AND variant = ?',
          variables: [Variable<String>(path), Variable<String>(variantKey)],
        )
        .get();

    return rows.isNotEmpty;
  }

  @override
  Future<Uint8List?> getBestVariant(String path) async {
    final rows = await _database
        .customSelect(
          'SELECT file FROM $_table WHERE path = ? '
          'ORDER BY (width IS NULL AND height IS NULL) DESC, '
          '(COALESCE(width, height, 0) * COALESCE(height, width, 0)) DESC '
          'LIMIT 1',
          variables: [Variable<String>(path)],
        )
        .get();

    return rows.isEmpty ? null : _readFile(rows.single.read<String>('file'));
  }

  @override
  Future<void> putVariant(
    String path,
    String variantKey,
    Uint8List bytes, {
    int? width,
    int? height,
  }) async {
    final fileName = _fileName(path, variantKey);
    await _fileFor(await _directory, fileName).writeAsBytes(bytes, flush: true);

    await _database.customStatement(
      'INSERT OR REPLACE INTO $_table (path, variant, file, width, height) VALUES (?, ?, ?, ?, ?)',
      [path, variantKey, fileName, width, height],
    );
  }

  @override
  Future<void> removePath(String path) async {
    final rows = await _database
        .customSelect(
          'SELECT file FROM $_table WHERE path = ?',
          variables: [Variable<String>(path)],
        )
        .get();

    final dir = await _directory;

    for (final row in rows) {
      await _deleteFile(_fileFor(dir, row.read<String>('file')));
    }

    await _database.customStatement('DELETE FROM $_table WHERE path = ?', [
      path,
    ]);
  }

  @override
  Future<List<String>> paths() async {
    final rows = await _database
        .customSelect('SELECT DISTINCT path FROM $_table')
        .get();

    return rows.map((row) => row.read<String>('path')).toList();
  }

  @override
  Future<void> clear() async {
    final rows = await _database.customSelect('SELECT file FROM $_table').get();
    final dir = await _directory;

    for (final row in rows) {
      await _deleteFile(_fileFor(dir, row.read<String>('file')));
    }

    await _database.customStatement('DELETE FROM $_table');
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone — nothing to reclaim.
    }
  }
}
