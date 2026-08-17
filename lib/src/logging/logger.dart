/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';

import '../fetcher/http_error.dart';
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

  const LogConfig({required this.level, required this.listeners});
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
void initializeLogger({Level? logLevel, List<LogListener>? listeners}) {
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
  Logger.root.onRecord.listen(
    (record) {
      final entry = degradeUnansweredRequest(record);

      if (entry == null) {
        return;
      }

      for (final listener in _listeners) {
        if (listener.isEnabled) {
          listener.onData(entry);
        }
      }
    },
    onError: (error, stackTrace) {
      for (final listener in _listeners) {
        if (listener.isEnabled) {
          listener.onError(error, stackTrace);
        }
      }
    },
    onDone: () {
      for (final listener in _listeners) {
        if (listener.isEnabled) {
          listener.onDone();
        }
      }
    },
    cancelOnError: false,
  );
}

/// Rewrites a record whose error is an unanswered request ([isServerUnavailable]:
/// no network, timeout, server in maintenance) into a single INFO line, and
/// returns any other record untouched. Null means the record is dropped.
///
/// Running on local data whenever the server is out of reach is the normal path
/// of an offline-first app, not a defect: call sites keep reporting the failure
/// they saw (`log.warning('Members load failed', error, stackTrace)`), and the
/// level is settled here, where the cause is known. The error and its trace are
/// dropped with it - they only ever restate the missing connection.
///
/// Demoting happens after [Logger.root.level] has filtered the record at its
/// original level, so the demoted line is dropped rather than shown below the
/// configured threshold.
LogRecord? degradeUnansweredRequest(LogRecord record) {
  final error = record.error;

  if (error == null ||
      record.level <= Level.INFO ||
      !isServerUnavailable(error)) {
    return record;
  }

  if (Level.INFO < Logger.root.level) {
    return null;
  }

  return LogRecord(
    Level.INFO,
    '${record.message}: ${describeUnavailable(error)}',
    record.loggerName,
    null,
    null,
    record.zone,
    record.object,
  );
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
    return const LogConfig(level: defaultLogLevel, listeners: []);
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

  return LogConfig(level: level, listeners: listeners);
}
