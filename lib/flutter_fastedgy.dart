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
/// - Dependency injection container
/// - Provider-based state management
/// - Internationalization support
/// - Logging utilities
library;

// Container (DI)
export 'src/container/container.dart';
export 'package:get_it/get_it.dart' show GetIt;
export 'package:injectable/injectable.dart';

// Event Bus
export 'src/bus/bus.dart';
export 'src/bus/events.dart';

// Logging
export 'src/logging/logging.dart';
export 'package:logging/logging.dart' show Level, Logger, LogRecord;
