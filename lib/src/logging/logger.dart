/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'console_log_handler.dart';
import 'log_handler.dart';

/// List of registered log handlers
final List<LogHandler> _handlers = [];

/// Initialize logging system with optional log level
///
/// If [logLevel] is not provided, it will be read from the environment
/// variable `LOG_LEVEL` if flutter_dotenv is initialized.
///
/// Example usage:
/// ```dart
/// await dotenv.load();
/// initializeLogger(); // Uses LOG_LEVEL from .env
/// // or
/// initializeLogger(logLevel: Level.INFO); // Explicit level
/// ```
void initializeLogger({Level? logLevel, List<LogHandler>? handlers}) {
  final level = logLevel ?? _parseLevelFromEnv();
  Logger.root.level = level;

  // Clear existing handlers
  _handlers.clear();

  // Add provided handlers or default to console
  if (handlers != null && handlers.isNotEmpty) {
    _handlers.addAll(handlers);
  } else {
    _handlers.add(ConsoleLogHandler());
  }

  // Setup logging
  Logger.root.onRecord.listen((record) {
    for (final handler in _handlers) {
      if (handler.isEnabled) {
        handler.handle(record);
      }
    }
  });
}

/// Add a custom log handler
void addLogHandler(LogHandler handler) {
  _handlers.add(handler);
}

/// Remove a log handler
void removeLogHandler(LogHandler handler) {
  _handlers.remove(handler);
}

/// Get a logger for a specific name
Logger getLogger(String name) {
  return Logger(name);
}

/// Parse log level from environment variable
Level _parseLevelFromEnv() {
  if (!dotenv.isInitialized) return Level.ALL;

  final levelStr = dotenv.env['LOG_LEVEL']?.toUpperCase();
  if (levelStr == null || levelStr.isEmpty) return Level.ALL;

  return Level.LEVELS.firstWhere(
    (level) => level.name == levelStr,
    orElse: () => Level.ALL,
  );
}
