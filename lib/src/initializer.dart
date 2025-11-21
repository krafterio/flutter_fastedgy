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
import 'fetcher/fetcher.dart';
import 'bus/bus.dart';

/// Initialize FastEdgy with default configuration
///
/// This function initializes:
/// - Environment variables from .env file
/// - Dependency injection container
/// - Logger system
/// - Internationalization (i18n)
/// - Authentication provider (default or custom)
///
/// Example:
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeFastEdgy(
///     authProvider: MyCustomAuthProvider(), // Optional
///   );
///   runApp(
///     useI18n(
///       supportedLocales: [Locale('en'), Locale('fr')],
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
Future<void> initializeFastEdgy({
  String? envFile,
  Level? logLevel,
  AuthProvider? authProvider,
}) async {
  await dotenv.load(fileName: envFile ?? '.env');
  initializeContainer();
  initializeLogger(logLevel: logLevel);
  await initializeI18n();

  // Register AuthProvider (custom or default)
  if (authProvider != null) {
    container.registerSingleton<AuthProvider>(authProvider);
  } else {
    // Register default implementation
    container.registerSingleton<AuthProvider>(
      DefaultAuthProvider(
        Fetcher.create(),
        getService<TokenStorage>(),
        getService<Bus>(),
      ),
    );
  }
}
