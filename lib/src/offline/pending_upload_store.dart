/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'offline_database.dart';

/// Scheme of the local reference standing in for a storage path until the file
/// is uploaded.
const localUploadScheme = 'local://';

/// The local reference addressing [id] before its upload.
String localUploadRef(String id) => '$localUploadScheme$id';

/// The pending upload id inside a local reference, or null for a real path.
String? pendingUploadIdOf(String? path) =>
    path != null && path.startsWith(localUploadScheme)
    ? path.substring(localUploadScheme.length)
    : null;

/// A file buffered on disk, waiting for its upload to be replayed.
class PendingUpload {
  final String id;
  final String fileName;
  final String? mimeType;
  final int sizeBytes;

  const PendingUpload({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    this.mimeType,
  });

  /// The reference a record carries while the file is still local.
  String get ref => localUploadRef(id);
}

/// Files buffered for a deferred upload: bytes on the filesystem, one index row
/// each in the offline database.
///
/// Unlike the image mirror — whose blobs are a cache, dropped as soon as no
/// mirrored record references them — these blobs are **owned by the outbox**:
/// they are the only copy of something the user produced, so nothing may
/// reclaim them until their operation was replayed or definitively abandoned.
///
/// Images are stored already optimized (the compression runs when the upload is
/// buffered, not when it is replayed), and are dropped once the server holds
/// the file: from then on the server rendition is the reference.
class PendingUploadStore {
  static const _table = '_pending_uploads';
  static const _directoryName = 'fastedgy_pending_uploads';

  final String dbName;
  final OfflineDatabase Function() _databaseOpener;
  final Future<Directory> Function() _directoryOpener;
  OfflineDatabase? _db;
  Directory? _dir;
  var _sequence = 0;

  /// Create a store whose index lives in [dbName] and whose bytes live under
  /// [directoryOpener] (defaults to the app support directory).
  ///
  /// [databaseOpener] and [directoryOpener] are test seams (in-memory drift
  /// database, temporary directory).
  PendingUploadStore({
    this.dbName = 'data.db',
    OfflineDatabase Function()? databaseOpener,
    Future<Directory> Function()? directoryOpener,
  }) : _databaseOpener = databaseOpener ?? (() => OfflineDatabase.open(dbName)),
       _directoryOpener = directoryOpener ?? getApplicationSupportDirectory;

  OfflineDatabase get _database {
    final db = _db;

    if (db == null) {
      throw StateError('PendingUploadStore is not open (call open() first)');
    }

    return db;
  }

  Future<Directory> get _directory async {
    final dir = _dir;

    if (dir != null) {
      return dir;
    }

    final base = await _directoryOpener();
    final resolved = Directory(p.join(base.path, _directoryName));
    await resolved.create(recursive: true);

    return _dir = resolved;
  }

  /// Open the underlying database (idempotent).
  Future<void> open() async {
    if (_db != null) {
      return;
    }

    final db = _databaseOpener();
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_table ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'file TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'mime TEXT, '
      'size INTEGER NOT NULL)',
    );
    _db = db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Buffer [bytes] and return its handle.
  ///
  /// [bytes] is what will be sent as-is: an image is expected already resized
  /// and re-encoded by the caller.
  Future<PendingUpload> put(
    Uint8List bytes, {
    required String fileName,
    String? mimeType,
  }) async {
    final id = _nextId();
    final file = File(p.join((await _directory).path, id));
    await file.writeAsBytes(bytes, flush: true);

    await _database.customStatement(
      'INSERT OR REPLACE INTO $_table (id, file, name, mime, size) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, id, fileName, mimeType, bytes.length],
    );

    return PendingUpload(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  Future<PendingUpload?> get(String id) async {
    final rows = await _database
        .customSelect(
          'SELECT id, name, mime, size FROM $_table WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .get();

    return rows.isEmpty ? null : _read(rows.single);
  }

  /// The buffered bytes, or null when the entry (or its file) is gone.
  Future<Uint8List?> bytes(String id) async {
    final rows = await _database
        .customSelect(
          'SELECT file FROM $_table WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .get();

    if (rows.isEmpty) {
      return null;
    }

    final file = File(
      p.join((await _directory).path, rows.single.read<String>('file')),
    );

    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<List<PendingUpload>> all() async {
    final rows = await _database
        .customSelect('SELECT id, name, mime, size FROM $_table ORDER BY id')
        .get();

    return rows.map(_read).toList();
  }

  /// Drop a buffered file: its upload succeeded (the server holds it now) or
  /// was definitively abandoned.
  Future<void> remove(String id) async {
    final rows = await _database
        .customSelect(
          'SELECT file FROM $_table WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .get();

    for (final row in rows) {
      await _deleteFile(
        File(p.join((await _directory).path, row.read<String>('file'))),
      );
    }

    await _database.customStatement('DELETE FROM $_table WHERE id = ?', [id]);
  }

  /// Drop everything (logout).
  Future<void> clearAll() async {
    final rows = await _database.customSelect('SELECT file FROM $_table').get();
    final dir = await _directory;

    for (final row in rows) {
      await _deleteFile(File(p.join(dir.path, row.read<String>('file'))));
    }

    await _database.customStatement('DELETE FROM $_table');
  }

  PendingUpload _read(QueryRow row) => PendingUpload(
    id: row.read<String>('id'),
    fileName: row.read<String>('name'),
    mimeType: row.readNullable<String>('mime'),
    sizeBytes: row.read<int>('size'),
  );

  // Same monotonic scheme as the outbox ids: sortable, collision-free within a
  // process, and filesystem-safe as a file name.
  String _nextId() {
    final now = DateTime.now();

    return '${now.microsecondsSinceEpoch.toString().padLeft(20, '0')}'
        '-${(_sequence++).toString().padLeft(4, '0')}';
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone — nothing to reclaim.
    }
  }
}
