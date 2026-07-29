/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_logger/easy_logger.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

/// Loads this package's own translations under the application's.
///
/// The widgets the package ships speak — a copy button, a placeholder, the
/// labels of the editor's "/" menu — and an application that never wrote those
/// keys would otherwise read English. Its own file always wins, so overriding
/// one string means writing it, not copying the rest.
class FastEdgyAssetLoader extends AssetLoader {
  final bool useOnlyLangCode;

  const FastEdgyAssetLoader({this.useOnlyLangCode = true});

  static const String _packagePath =
      'packages/flutter_fastedgy/assets/translations';

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final name = useOnlyLangCode
        ? locale.languageCode
        : [locale.languageCode, ?locale.countryCode].join('_');

    final framework = await _read('$_packagePath/$name.json');
    final application = await _read('$path/$name.json');

    if (framework == null && application == null) {
      return null;
    }

    return {...?framework, ...?application};
  }

  /// Null where the file is not there, which is the normal case for a locale
  /// one side supports and the other does not.
  Future<Map<String, dynamic>?> _read(String asset) async {
    try {
      return jsonDecode(await rootBundle.loadString(asset))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

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
    assetLoader: FastEdgyAssetLoader(useOnlyLangCode: useOnlyLangCode),
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
