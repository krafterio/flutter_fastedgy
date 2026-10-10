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
///
/// Everything core.dart gives, with the localizations of Material and
/// Cupertino in `context.fastEdgyLocalizationDelegates` and the former name
/// of ApiImageCache: it pulls Material and Cupertino in. An application that
/// wants neither imports core.dart.
library;

export 'core.dart' hide FastEdgyWidgetsLocalizations;
export 'cupertino.dart';
export 'material.dart';
export 'src/i18n/platform_localizations.dart';
export 'src/image/legacy_names.dart';
