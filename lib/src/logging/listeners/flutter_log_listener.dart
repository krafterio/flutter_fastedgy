/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:developer' as developer;

import 'package:logging/logging.dart';

import '../log_listener.dart';

class FlutterLogListener implements LogListener {
  @override
  bool get isEnabled => true;

  @override
  void onData(LogRecord record) {
    final error = record.error;
    final stackTrace = record.stackTrace;

    // An error handed apart is printed on a line of its own, which is two
    // lines for one event: what a failure answered belongs to the sentence
    // saying it failed. A trace keeps them apart, since it needs its error to
    // be read as the start of the stack.
    developer.log(
      error == null || stackTrace != null
          ? record.message
          : '${record.message}: $error',
      time: record.time,
      sequenceNumber: record.sequenceNumber,
      level: record.level.value,
      name: record.loggerName.isNotEmpty ? record.loggerName : 'app',
      error: stackTrace == null ? null : error,
      stackTrace: stackTrace,
    );
  }

  @override
  void onError(Object error, StackTrace stackTrace) {}

  @override
  void onDone() {}
}
