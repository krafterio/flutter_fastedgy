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

  void follow() {
    unawaited(changeSubscription?.cancel());
    changeSubscription = changes.listen(
      controller.add,
      onError: controller.addError,
    );
  }

  controller = StreamController<bool>(
    onListen: () {
      follow();
      resumeSubscription = resumes
          .asyncMap((_) {
            follow();

            return check();
          })
          .listen(controller.add, onError: (Object _) {});
    },
    onCancel: () async {
      await changeSubscription?.cancel();
      await resumeSubscription?.cancel();
    },
  );

  return controller.stream;
}
