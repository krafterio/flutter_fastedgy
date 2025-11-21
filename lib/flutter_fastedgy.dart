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

// Core
export 'src/initializer.dart';

// Container (DI)
export 'src/container/container.dart' show
  container,
  initializeContainer,
  getService,
  hasService,
  singleton,
  lazySingleton,
  injectable;

// Event Bus
export 'src/bus/bus.dart';
export 'src/bus/events.dart';

// Logging
export 'src/logging/logging.dart';
export 'package:logging/logging.dart' show Level, Logger, LogRecord;

// I18n
export 'src/i18n/i18n.dart';
export 'package:flutter/widgets.dart' show Locale;
export 'package:easy_localization/easy_localization.dart'
  show StringTranslateExtension, BuildContextEasyLocalizationExtension;

// Fetcher
export 'src/fetcher/fetcher_module.dart';
export 'package:dio/dio.dart' show Response, ResponseType;
