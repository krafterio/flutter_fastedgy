/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'container/container.dart';
import 'i18n/i18n.dart';
import 'logging/logger.dart';

/// Initialize FastEdgy with default configuration
///
/// This function initializes:
/// - Environment variables from .env file
/// - Dependency injection container
/// - Logger system
/// - Internationalization (i18n)
///
/// Example:
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeFastEdgy();
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
}) async {
  await dotenv.load(fileName: envFile ?? '.env');
  initializeContainer();
  initializeLogger(logLevel: logLevel);
  await initializeI18n();
}
