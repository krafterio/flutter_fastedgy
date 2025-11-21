/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'container/container.dart';
import 'i18n/i18n.dart';
import 'logging/logger.dart';
import 'auth/auth_provider.dart';
import 'auth/default_auth_provider.dart';
import 'auth/token_storage.dart';
import 'fetcher/client.dart';
import 'bus/bus.dart';

/// Initialize FastEdgy with default configuration
///
/// This function initializes:
/// - Environment variables from .env file
/// - Dependency injection container
/// - Logger system
/// - Internationalization (i18n)
/// - All core services (Bus, TokenStorage, etc.)
/// - Authentication provider (default or custom)
///
/// You can override any service by providing your own implementation.
///
/// Example:
/// ```dart
/// // Default usage
/// await initializeFastEdgy();
///
/// // With custom services
/// await initializeFastEdgy(
///   bus: MyCustomBus(),
///   tokenStorage: MyCustomTokenStorage(),
///   authProvider: MyCustomAuthProvider(),
/// );
/// ```
Future<void> initializeFastEdgy({
  String? envFile,
  Level? logLevel,

  // Core services (overridable)
  Bus? bus,
  Fetcher? fetcher,
  TokenStorage? tokenStorage,
  AuthProvider? authProvider,
}) async {
  await dotenv.load(fileName: envFile ?? '.env');

  // Initialize container
  initializeContainer();

  // Register core services
  container.registerSingleton<Bus>(
    bus ?? Bus(),
  );

  container.registerSingleton<Fetcher>(
    fetcher ?? Fetcher.create(),
  );

  container.registerSingleton<TokenStorage>(
    tokenStorage ?? TokenStorage(),
  );

  initializeLogger(logLevel: logLevel);
  await initializeI18n();

  container.registerSingleton<AuthProvider>(
    authProvider ?? DefaultAuthProvider(
      getService<Fetcher>(),
      getService<TokenStorage>(),
      getService<Bus>(),
    ),
  );
}
