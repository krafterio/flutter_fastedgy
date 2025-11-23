/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:logging/logging.dart';

/// Abstract interface for log listeners
abstract class LogListener {
  /// Whether this listener is enabled
  bool get isEnabled => true;

  /// Handle a log record
  void onData(LogRecord record) {}

  /// Handle an error
  void onError(Object error, StackTrace stackTrace) {}

  /// Handle a done event
  void onDone() {}
}
