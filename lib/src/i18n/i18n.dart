/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_logger/easy_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

/// Initialize EasyLocalization
///
/// This is called automatically by initializeFastEdgy().
Future<void> initializeI18n() async {
  EasyLocalization.logger.enableLevels = _mapLogLevelToEasyLogger(
    Logger.root.level,
  );
  await EasyLocalization.ensureInitialized();
}

/// Wrap your app with i18n support
///
/// This must be used in runApp() after calling initializeFastEdgy().
///
/// IMPORTANT: You MUST also configure your App (MaterialApp, CupertinoApp, etc) with:
/// ```dart
/// // In your App widget build method:
/// MaterialApp( // or CupertinoApp, or WidgetsApp
///   localizationsDelegates: context.localizationDelegates,
///   supportedLocales: context.supportedLocales,
///   locale: context.locale,
///   // ... rest of your app config
/// )
/// ```
///
/// Complete example:
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeFastEdgy();
///
///   runApp(
///     useI18n(
///       supportedLocales: [Locale('en'), Locale('fr')],
///       child: MyApp(),
///     ),
///   );
/// }
///
/// class MyApp extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       localizationsDelegates: context.localizationDelegates,
///       supportedLocales: context.supportedLocales,
///       locale: context.locale,
///       home: HomeScreen(),
///     );
///   }
/// }
/// ```
Widget useI18n({
  required List<Locale> supportedLocales,
  required Widget child,
  Locale? fallbackLocale,
  String translationsPath = 'assets/translations',
  bool useOnlyLangCode = true,
  bool useFallbackTranslations = true,
  bool saveLocale = true,
}) {
  return EasyLocalization(
    supportedLocales: supportedLocales,
    path: translationsPath,
    fallbackLocale: fallbackLocale ?? supportedLocales.first,
    useOnlyLangCode: useOnlyLangCode,
    useFallbackTranslations: useFallbackTranslations,
    saveLocale: saveLocale,
    child: child,
  );
}

/// Translate a string key
///
/// Example:
/// ```dart
/// final text = t('hello');
/// final textWithParams = t('welcome', {'name': 'John'});
/// ```
String t(String key, [Map<String, String>? namedArgs]) {
  return key.tr(namedArgs: namedArgs);
}

/// Translate a string key with plural support
///
/// Example:
/// ```dart
/// final text = plural('item', 5); // "5 items"
/// final textWithParams = plural('item_with_name', 5, {'name': 'John'});
/// ```
String plural(String key, num value, [Map<String, String>? namedArgs]) {
  return key.plural(value, namedArgs: namedArgs);
}

/// Get current locale
Locale currentLocale(BuildContext context) {
  return context.locale;
}

/// Set current locale
Future<void> setLocale(BuildContext context, Locale locale) async {
  await context.setLocale(locale);
}

/// Get supported locales
List<Locale> supportedLocales(BuildContext context) {
  return context.supportedLocales;
}

/// Map logging Level to EasyLogger levels
List<LevelMessages> _mapLogLevelToEasyLogger(Level level) {
  final levels = <LevelMessages>[];

  if (level <= Level.SEVERE) {
    levels.add(LevelMessages.error);
  }

  if (level <= Level.WARNING) {
    levels.add(LevelMessages.warning);
  }

  if (level <= Level.INFO) {
    levels.add(LevelMessages.info);
  }

  if (level <= Level.CONFIG) {
    levels.add(LevelMessages.debug);
  }

  return levels;
}
