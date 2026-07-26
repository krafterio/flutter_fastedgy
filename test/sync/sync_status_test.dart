/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  group('SyncStatus', () {
    late Bus bus;
    late List<SyncStatusChangedEvent> events;
    late SyncStatus status;

    setUp(() {
      bus = Bus();
      events = [];
      bus.on<SyncStatusChangedEvent>().listen(events.add);
      status = SyncStatus(bus, online: true);
    });

    test('starts from the seeded online state, idle and empty', () {
      expect(status.online, isTrue);
      expect(status.syncing, isFalse);
      expect(status.pending, 0);
      expect(status.isActive, isFalse);
    });

    test(
      'a changed field fires one snapshot event and notifies listeners',
      () async {
        var notified = 0;
        status.addListener(() => notified++);

        status.setPending(3);
        await Future<void>.delayed(Duration.zero);

        expect(status.pending, 3);
        expect(status.isActive, isTrue);
        expect(notified, 1);
        expect(events, hasLength(1));
        expect(events.single.online, isTrue);
        expect(events.single.syncing, isFalse);
        expect(events.single.pending, 3);
      },
    );

    test('setting a field to its current value is a no-op', () async {
      status.setPending(0);
      status.setOnline(true);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('offline or syncing or a non-empty queue makes it active', () {
      status.setOnline(false);
      expect(status.isActive, isTrue);

      status.setOnline(true);
      status.setSyncing(true);
      expect(status.isActive, isTrue);

      status.setSyncing(false);
      expect(status.isActive, isFalse);
    });
  });

  group('Outbox.onChanged', () {
    test('reports the pending count on enqueue and remove', () async {
      OfflineDatabase.allowMultipleInstances();
      final store = DriftLocalStore(
        databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
      );
      await store.open();

      final counts = <int>[];
      final outbox = Outbox(store, onChanged: counts.add);

      final op = await outbox.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: 'PATCH',
          basePath: '/items',
          recordId: 1,
          payload: const {'name': 'x'},
          createdAt: createdAt,
          cache: const OutboxCacheContext(kind: 'json', namespace: '/items'),
        ),
      );
      await outbox.remove(op.id);

      expect(counts, [1, 0]);

      await store.close();
    });
  });
}
