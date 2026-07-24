/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  late Directory directory;
  late OfflineDatabase db;

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    directory = await Directory.systemTemp.createTemp('offline_database_test');
    db = OfflineDatabase(
      NativeDatabase(
        File('${directory.path}/data.db.sqlite'),
        setup: applyOfflineDatabasePragmas,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  group('applyOfflineDatabasePragmas', () {
    // Several app instances (or Flutter engines) open the same file: without
    // WAL a writer locks out every reader, and without a busy timeout a
    // concurrent lock fails instantly with `database is locked`.
    test('opens the database in WAL mode', () async {
      final row = await db.customSelect('pragma journal_mode').getSingle();

      expect(row.read<String>('journal_mode'), 'wal');
    });

    test('waits on a lock held by another connection', () async {
      final row = await db.customSelect('pragma busy_timeout').getSingle();

      expect(row.read<int>('timeout'), greaterThan(0));
    });
  });
}
