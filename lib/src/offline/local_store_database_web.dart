/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:sembast_web/sembast_web.dart';

/// Open the offline database backed by IndexedDB.
Future<Database> openOfflineDatabase(String name) {
  return databaseFactoryWeb.openDatabase(name);
}
