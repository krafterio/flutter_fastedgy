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
    developer.log(
      record.message,
      time: record.time,
      sequenceNumber: record.sequenceNumber,
      level: record.level.value,
      name: record.loggerName.isNotEmpty ? record.loggerName : 'app',
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }

  @override
  void onError(Object error, StackTrace stackTrace) {}

  @override
  void onDone() {}
}
