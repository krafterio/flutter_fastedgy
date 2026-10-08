/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/src/sync/connectivity_watch.dart';

void main() {
  test('passes the connectivity changes through', () async {
    final changes = StreamController<bool>();
    final seen = <bool>[];
    final subscription = watchConnectivity(
      changes: changes.stream,
      resumes: const Stream.empty(),
      check: () async => true,
    ).listen(seen.add);
    addTearDown(subscription.cancel);

    changes
      ..add(false)
      ..add(true);
    await pumpEventQueue();

    expect(seen, [false, true]);
  });

  test('reads the connectivity again when the app comes back, the change made in the background was dropped', () async {
    final resumes = StreamController<void>();
    var connected = true;
    final seen = <bool>[];
    final subscription = watchConnectivity(
      changes: const Stream.empty(),
      resumes: resumes.stream,
      check: () async => connected,
    ).listen(seen.add);
    addTearDown(subscription.cancel);

    connected = false;
    resumes.add(null);
    await pumpEventQueue();

    expect(seen, [false]);
  });

  test('a failed read on resume keeps the last known state', () async {
    final resumes = StreamController<void>();
    final seen = <bool>[];
    final errors = <Object>[];
    final subscription = watchConnectivity(
      changes: const Stream.empty(),
      resumes: resumes.stream,
      check: () async => throw StateError('no answer'),
    ).listen(seen.add, onError: errors.add);
    addTearDown(subscription.cancel);

    resumes.add(null);
    await pumpEventQueue();

    expect(seen, isEmpty);
    expect(errors, isEmpty);
  });
}
