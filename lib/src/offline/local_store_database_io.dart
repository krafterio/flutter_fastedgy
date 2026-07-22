/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast_sqflite/sembast_sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

/// Open the offline database as a SQLite file in the application support
/// directory.
///
/// Uses the native `sqflite` plugin on Android/iOS/macOS and the FFI
/// implementation on Windows/Linux (which requires a sqlite3 dynamic library
/// available on the system, or `sqlite3_flutter_libs` once those platforms
/// are enabled).
Future<Database> openOfflineDatabase(String name) async {
  final directory = await getApplicationSupportDirectory();
  final path = p.join(directory.path, name);

  return getDatabaseFactorySqflite(_sqfliteFactory()).openDatabase(path);
}

sqflite.DatabaseFactory _sqfliteFactory() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return sqflite.databaseFactory;
  }

  sqflite_ffi.sqfliteFfiInit();

  return sqflite_ffi.databaseFactoryFfi;
}
