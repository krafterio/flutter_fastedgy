/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:sembast/sembast.dart';

/// Open the offline database for the current platform.
Future<Database> openOfflineDatabase(String name) {
  throw UnsupportedError(
    'Offline local store is not supported on this platform',
  );
}
