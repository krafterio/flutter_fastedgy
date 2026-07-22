/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Platform-specific sembast database opener.
///
/// Selects the storage backend at compile time:
/// - io platforms: SQLite file via `sembast_sqflite` (`sqflite` on
///   Android/iOS/macOS, `sqflite_common_ffi` on Windows/Linux)
/// - web: IndexedDB via `sembast_web`
library;

export 'local_store_database_stub.dart'
    if (dart.library.io) 'local_store_database_io.dart'
    if (dart.library.js_interop) 'local_store_database_web.dart';
