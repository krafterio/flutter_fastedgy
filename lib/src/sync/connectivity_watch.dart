/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

Stream<bool> watchConnectivity({
  required Stream<bool> changes,
  required Stream<void> resumes,
  required Future<bool> Function() check,
}) {
  late final StreamController<bool> controller;
  StreamSubscription<bool>? changeSubscription;
  StreamSubscription<bool>? resumeSubscription;

  controller = StreamController<bool>(
    onListen: () {
      changeSubscription = changes.listen(
        controller.add,
        onError: controller.addError,
      );
      resumeSubscription = resumes
          .asyncMap((_) => check())
          .listen(controller.add, onError: (Object _) {});
    },
    onCancel: () async {
      await changeSubscription?.cancel();
      await resumeSubscription?.cancel();
    },
  );

  return controller.stream;
}
