/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  late LocalSequence sequence;

  setUp(() async {
    sequence = LocalSequence(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await sequence.open();
  });

  tearDown(() => sequence.close());

  group('LocalSequence', () {
    test('allocates temporary ids downwards from -1', () async {
      expect(await sequence.nextTempId('flow'), -1);
      expect(await sequence.nextTempId('flow'), -2);
      expect(await sequence.nextTempId('flow'), -3);
    });

    test('scopes temporary ids per model', () async {
      expect(await sequence.nextTempId('flow'), -1);
      expect(await sequence.nextTempId('attachment'), -1);
      expect(await sequence.nextTempId('attachment'), -2);

      // Per-model counters overlap by design; the replay disambiguates them
      // through the model, never through the value.
      expect(await sequence.nextTempId('flow'), -2);
    });

    test('allocates placeholder counters upwards from 1', () async {
      expect(await sequence.nextPlaceholder('flow', 'reference'), 1);
      expect(await sequence.nextPlaceholder('flow', 'reference'), 2);
    });

    test('scopes placeholder counters per model and field', () async {
      expect(await sequence.nextPlaceholder('flow', 'reference'), 1);
      expect(await sequence.nextPlaceholder('flow', 'code'), 1);
      expect(await sequence.nextPlaceholder('ticket', 'reference'), 1);
      expect(await sequence.nextPlaceholder('flow', 'reference'), 2);
    });

    test('keeps temporary ids and placeholders on separate counters', () async {
      expect(await sequence.nextTempId('flow'), -1);

      // Same model, unrelated counter: the placeholder must not inherit -1.
      expect(await sequence.nextPlaceholder('flow', 'reference'), 1);
    });

    test('never hands out the same id under concurrent allocation', () async {
      // Allocation must be one statement: a read-then-write would let these
      // interleave and return duplicates.
      final ids = await Future.wait([
        for (var i = 0; i < 50; i++) sequence.nextTempId('flow'),
      ]);

      expect(ids.toSet(), hasLength(50));
      expect(ids.reduce((a, b) => a < b ? a : b), -50);
      expect(ids.reduce((a, b) => a > b ? a : b), -1);
    });

    test('peek reports the current value without allocating', () async {
      expect(await sequence.peek('temp_id:flow'), isNull);

      await sequence.nextTempId('flow');

      expect(await sequence.peek('temp_id:flow'), -1);
      expect(await sequence.peek('temp_id:flow'), -1);
      expect(await sequence.nextTempId('flow'), -2);
    });

    test('clearAll restarts every counter', () async {
      await sequence.nextTempId('flow');
      await sequence.nextTempId('flow');
      await sequence.nextPlaceholder('flow', 'reference');

      await sequence.clearAll();

      expect(await sequence.nextTempId('flow'), -1);
      expect(await sequence.nextPlaceholder('flow', 'reference'), 1);
    });

    test('survives a reopen on the same database', () async {
      OfflineDatabase.allowMultipleInstances();

      final db = OfflineDatabase(NativeDatabase.memory());
      final first = LocalSequence(databaseOpener: () => db);
      await first.open();

      expect(await first.nextTempId('flow'), -1);

      final second = LocalSequence(databaseOpener: () => db);
      await second.open();

      // Same file, same counter: a second instance keeps counting down.
      expect(await second.nextTempId('flow'), -2);

      await second.close();
    });

    test('rejects use before open', () async {
      final closed = LocalSequence(
        databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
      );

      expect(() => closed.nextTempId('flow'), throwsStateError);
    });
  });
}
