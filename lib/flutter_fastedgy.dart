/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Flutter package to facilitate integration between a FastEdgy server
/// and a Flutter application.
///
/// This package provides:
/// - HTTP client with automatic authentication
/// - JWT token management
/// - Event bus for application-wide events
/// - Provider-based state management
/// - Internationalization support
/// - Logging utilities
library;

// Logging
export 'src/logging/logging.dart';
export 'package:logging/logging.dart' show Level, Logger, LogRecord;
