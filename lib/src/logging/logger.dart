/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import './listeners/console_log_listener.dart';
import './listeners/flutter_log_listener.dart';
import './log_listener.dart';

/// List of registered log listeners
final List<LogListener> _listeners = [];

const defaultLogLevel = Level.INFO;

/// Configuration for the logging system
class LogConfig {
  /// The log level
  final Level level;

  /// The list of log listeners
  final List<String> listeners;

  const LogConfig({
    required this.level,
    required this.listeners,
  });
}

/// Initialize logging system with optional log level
///
/// If [logLevel] is not provided, it will be read from the environment
/// variable `LOG_LEVEL` if flutter_dotenv is initialized.
///
/// If [listeners] is not provided, it will be read from the environment
/// variable `LOG_OUTPUT` if flutter_dotenv is initialized.
///
/// Example usage:
/// ```dart
/// await dotenv.load();
/// initializeLogger(); // Uses LOG_LEVEL from .env
/// // or
/// initializeLogger(logLevel: Level.INFO); // Explicit level
/// // or
/// initializeLogger(listeners: [FlutterLogListener()]); // Explicit listeners
/// ```
void initializeLogger({
  Level? logLevel,
  List<LogListener>? listeners,
}) {
  final config = parseLogConfigFromEnv();
  final level = logLevel ?? config.level;
  Logger.root.level = level;

  // Clear existing listeners
  _listeners.clear();

  // Add default listeners
  if (config.listeners.contains('console')) {
    _listeners.add(ConsoleLogListener());
  }

  if (config.listeners.contains('flutter')) {
    _listeners.add(FlutterLogListener());
  }

  // Add provided listeners
  if (listeners != null && listeners.isNotEmpty) {
    _listeners.addAll(listeners);
  }

  // Setup logging
  Logger.root.onRecord.listen((record) {
    for (final listener in _listeners) {
      if (listener.isEnabled) {
        listener.onData(record);
      }
    }
  }, onError: (error, stackTrace) {
    for (final listener in _listeners) {
      if (listener.isEnabled) {
        listener.onError(error, stackTrace);
      }
    }
  }, onDone: () {
    for (final listener in _listeners) {
      if (listener.isEnabled) {
        listener.onDone();
      }
    }
  }, cancelOnError: false);
}

/// Add a custom log listener
void addLogListener(LogListener listener) {
  _listeners.add(listener);
}

/// Remove a log listener
void removeLogListener(LogListener listener) {
  _listeners.remove(listener);
}

/// Get a logger for a specific name
Logger getLogger(String name) {
  return Logger(name);
}

/// Parse log config from environment variable
LogConfig parseLogConfigFromEnv() {
  if (!dotenv.isInitialized) {
    return const LogConfig(
      level: defaultLogLevel,
      listeners: [],
    );
  }

  final levelStr = dotenv.env['LOG_LEVEL']?.toUpperCase();
  final level = levelStr == null || levelStr.isEmpty
      ? defaultLogLevel
      : Level.LEVELS.firstWhere(
          (l) => l.name == levelStr,
          orElse: () => defaultLogLevel,
        );

  final outputStr = dotenv.env['LOG_OUTPUT']?.toLowerCase();
  final listeners = outputStr?.split(',') ?? [];

  return LogConfig(
    level: level,
    listeners: listeners,
  );
}
