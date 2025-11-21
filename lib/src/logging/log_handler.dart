/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:logging/logging.dart';

/// Abstract interface for log handlers
abstract class LogHandler {
  /// Handle a log record
  void handle(LogRecord record);

  /// Whether this handler is enabled
  bool get isEnabled => true;
}
