/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/cupertino.dart';
import 'package:logging/logging.dart';
import '../log_listener.dart';

/// Console log listener using print
class ConsoleLogListener implements LogListener {
  @override
  bool get isEnabled => true;

  @override
  void onData(LogRecord record) {
    debugPrint(record.toString());

    if (record.error != null && record.stackTrace != null) {
      onError(record.error!, record.stackTrace!);
    } else if (record.error != null) {
      onError(record.error!, StackTrace.empty);
    } else if (record.stackTrace != null) {
      onError(Exception('No error provided'), record.stackTrace!);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    debugPrint('Error: $error');

    if (stackTrace != StackTrace.empty) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  void onDone() {}
}
