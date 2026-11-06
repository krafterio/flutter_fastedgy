/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:drift/native.dart';

import 'dart:ui' show AppExitResponse;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  _closesOnExit();

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

void _closesOnExit() {
  testWidgets('the shared database is closed when the app is asked to exit', (
    tester,
  ) async {
    OfflineDatabase.allowMultipleInstances();
    final database = OfflineDatabase(NativeDatabase.memory());
    final listener = closeOnExit(() => database);
    addTearDown(listener.dispose);
    await database.customSelect('select 1').get();

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);

    await expectLater(
      database.customSelect('select 1').get(),
      throwsA(anything),
    );
  });
}
