/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_logger/easy_logger.dart';
import 'package:flutter/foundation.dart'
    show SynchronousFuture, ValueListenable, ValueNotifier;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

/// Loads the application's translations, and the packages' apart.
///
/// The widgets a package ships speak (a copy button, a placeholder, the labels
/// of the editor's "/" menu) with keys written in its own source language,
/// while the application may write its keys in another one: each side keeps
/// its catalogs, and [t] tells which one a key belongs to. Every catalog a
/// package ships under `assets/translations` is read, found in the asset
/// manifest, so its keys are known whatever the language displayed, its
/// source language included, which needs no file.
class FastEdgyAssetLoader extends AssetLoader {
  final bool useOnlyLangCode;

  const FastEdgyAssetLoader({this.useOnlyLangCode = true});

  static final _packageCatalog = RegExp(
    r'^packages/([^/]+)/assets/translations/([^/]+)\.json$',
  );

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final name = useOnlyLangCode
        ? locale.languageCode
        : [locale.languageCode, ?locale.countryCode].join('_');

    await (_packagesLoading ??= _loadPackages());

    final words = await _read('$path/$name.json');
    _appWords[locale.languageCode] = words ?? const {};

    return words;
  }

  Future<void> _loadPackages() async {
    final List<String> assets;

    try {
      assets = (await AssetManifest.loadFromAssetBundle(rootBundle))
          .listAssets();
    } catch (_) {
      return;
    }

    await Future.wait([
      for (final asset in assets)
        if (_packageCatalog.firstMatch(asset) case final match?)
          _read(asset).then(
            (words) => _packageWords.putIfAbsent(
              match.group(1)!,
              () => {},
            )[match.group(2)!] = words ?? const {},
          ),
    ]);
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

extension FastEdgyLocalizations on BuildContext {
  /// The delegates an application's App widget must be given.
  ///
  /// `context.localizationDelegates` alone is not enough: it carries the
  /// globals of `flutter_localizations`, which localize the Material and
  /// Cupertino still shipped inside `package:flutter`. Since Flutter 3.47 the
  /// widgets actually rendered come from `material_ui` and `cupertino_ui`,
  /// whose localizations are distinct types, and a locale other than English
  /// finds none of them.
  List<LocalizationsDelegate> get fastEdgyLocalizationDelegates => [
    ...localizationDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    const _ActiveLocaleDelegate(),
  ];
}

ValueListenable<Locale?> get activeLocale => _ActiveLocaleDelegate.locale;

class _ActiveLocale {
  const _ActiveLocale();
}

class _ActiveLocaleDelegate extends LocalizationsDelegate<_ActiveLocale> {
  const _ActiveLocaleDelegate();

  static final locale = ValueNotifier<Locale?>(null);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<_ActiveLocale> load(Locale locale) {
    final region =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final regional = region == null ? null : '${locale.languageCode}_$region';

    Intl.defaultLocale = regional != null && DateFormat.localeExists(regional)
        ? regional
        : locale.languageCode;
    _ActiveLocaleDelegate.locale.value = locale;

    return SynchronousFuture(const _ActiveLocale());
  }

  @override
  bool shouldReload(_ActiveLocaleDelegate old) => false;
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
/// The options are the ones every FastEdgy client shares:
/// - `availableLocales`: the languages the app offers.
/// - `locale`: the language the app gives, the account's for instance. Without
///   it, the language chosen on the device, then the device's own, then
///   `fallbackLocale`.
/// - `fallbackLocale`: the language of whoever speaks none of the others, and
///   where a missing translation is looked up next.
/// - `sourceLocale`: the language the application writes its keys in,
///   `fallbackLocale` when not given. It goes from its own translations
///   straight to the key.
/// - `packageSourceLocales`: the language a package writes its keys in, by
///   package name, for a package not written in English.
///
/// IMPORTANT: You MUST also configure your App (MaterialApp, CupertinoApp, etc) with:
/// ```dart
/// // In your App widget build method:
/// MaterialApp( // or CupertinoApp, or WidgetsApp
///   localizationsDelegates: context.fastEdgyLocalizationDelegates,
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
///       availableLocales: [Locale('en'), Locale('fr')],
///       child: MyApp(),
///     ),
///   );
/// }
///
/// class MyApp extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       localizationsDelegates: context.fastEdgyLocalizationDelegates,
///       supportedLocales: context.supportedLocales,
///       locale: context.locale,
///       home: HomeScreen(),
///     );
///   }
/// }
/// ```
Widget useI18n({
  required List<Locale> availableLocales,
  required Widget child,
  Locale? locale,
  Locale? fallbackLocale,
  Locale? sourceLocale,
  Map<String, Locale> packageSourceLocales = const {},
  String translationsPath = 'assets/translations',
  bool useOnlyLangCode = true,
  bool useFallbackTranslations = true,
  bool saveLocale = true,
}) {
  final fallback = fallbackLocale ?? availableLocales.first;
  final given = locale == null ? null : _availableIn(availableLocales, locale);
  _sourceLocale = sourceLocale ?? fallback;
  _fallbackLanguage = fallback.languageCode;
  _packageSourceLocales = packageSourceLocales;
  _appWords.clear();
  _packageWords.clear();
  _packagesLoading = null;

  return EasyLocalization(
    supportedLocales: availableLocales,
    path: translationsPath,
    assetLoader: FastEdgyAssetLoader(useOnlyLangCode: useOnlyLangCode),
    startLocale: given ?? _deviceLocaleIn(availableLocales, fallback),
    fallbackLocale: fallback,
    useOnlyLangCode: useOnlyLangCode,
    useFallbackTranslations: useFallbackTranslations,
    saveLocale: saveLocale,
    child: _DeviceLocaleFollower(locale: given, child: child),
  );
}

ValueListenable<Locale?> get chosenLocale => _chosenLocale;

final _chosenLocale = ValueNotifier<Locale?>(null);

Future<void> chooseLocale(BuildContext context, Locale locale) async {
  _chosenLocale.value = locale;
  await EasyLocalization.of(context)!.setLocale(locale);
}

Future<void> followDeviceLocale(BuildContext context) async {
  _chosenLocale.value = null;
  final localization = EasyLocalization.of(context)!;
  final available = localization.supportedLocales;

  await localization.setLocale(
    _deviceLocaleIn(available, localization.fallbackLocale ?? available.first),
  );
  await localization.deleteSaveLocale();
}

Locale _deviceLocaleIn(List<Locale> available, Locale fallback) =>
    _availableIn(
      available,
      WidgetsBinding.instance.platformDispatcher.locale,
    ) ??
    fallback;

Locale? _availableIn(List<Locale> available, Locale locale) {
  for (final candidate in available) {
    if (candidate.languageCode == locale.languageCode) {
      return candidate;
    }
  }

  return null;
}

class _DeviceLocaleFollower extends StatefulWidget {
  const _DeviceLocaleFollower({required this.locale, required this.child});

  final Locale? locale;
  final Widget child;

  @override
  State<_DeviceLocaleFollower> createState() => _DeviceLocaleFollowerState();
}

class _DeviceLocaleFollowerState extends State<_DeviceLocaleFollower>
    with WidgetsBindingObserver {
  var _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final given = widget.locale;
      _chosenLocale.value = given ?? context.savedLocale;

      if (given != null && context.locale != given) {
        unawaited(chooseLocale(context, given));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_chosenLocale.value == null) {
      unawaited(followDeviceLocale(context));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Translate a string key
///
/// Example:
/// ```dart
/// final text = t('hello');
/// final textWithParams = t('welcome', {'name': 'John'});
/// ```
String t(String key, [Map<String, String>? namedArgs]) {
  final package = _packageKnowing(key);

  if (package != null) {
    return _withArguments(_packageWord(package, key) ?? key, namedArgs);
  }

  if (_speaksSource() && !trExists(key)) {
    return _withArguments(key, namedArgs);
  }

  return key.tr(namedArgs: namedArgs);
}

String _withArguments(String text, Map<String, String>? namedArgs) =>
    namedArgs == null
    ? text
    : namedArgs.entries.fold(
        text,
        (text, arg) => text.replaceAll('{${arg.key}}', arg.value),
      );

class TranslatableString {
  final String message;
  final Map<String, String>? namedArgs;

  const TranslatableString(this.message, [this.namedArgs]);

  String render() => t(message, namedArgs);

  @override
  String toString() => render();
}

TranslatableString ts(String message, [Map<String, String>? namedArgs]) =>
    TranslatableString(message, namedArgs);

Locale? _sourceLocale;

Future<void>? _packagesLoading;

const _packageSourceLanguage = 'en';

String? _fallbackLanguage;

Map<String, Locale> _packageSourceLocales = const {};

final _appWords = <String, Map<String, dynamic>>{};

/// The catalogs of each package, by package name, then by language.
final _packageWords = <String, Map<String, Map<String, dynamic>>>{};

/// The package a key belongs to: the first package knowing it, unless the
/// application knows it too, and has the last word.
String? _packageKnowing(String key) {
  if (_appWords.values.any((words) => words.containsKey(key))) {
    return null;
  }

  for (final MapEntry(key: package, value: catalogs) in _packageWords.entries) {
    if (catalogs.values.any((words) => words.containsKey(key))) {
      return package;
    }
  }

  return null;
}

/// A package word in the displayed language, then in `fallbackLocale`. A
/// package writes its keys in English unless the application says otherwise,
/// and in that language they are the text already.
String? _packageWord(String package, String key) {
  final active = activeLocale.value?.languageCode;
  final source =
      _packageSourceLocales[package]?.languageCode ?? _packageSourceLanguage;

  if (active == null || active == source) {
    return null;
  }

  final catalogs = _packageWords[package] ?? const {};
  final word = catalogs[active]?[key];

  if (word is String) {
    return word;
  }

  EasyLocalization.logger.warning('Localization key [$key] not found');
  final fallback = _fallbackLanguage == source
      ? null
      : catalogs[_fallbackLanguage]?[key];

  return fallback is String ? fallback : null;
}

bool _speaksSource() {
  final source = _sourceLocale;
  final active = activeLocale.value;

  return source != null &&
      active != null &&
      active.languageCode == source.languageCode;
}

/// Translate a string key with plural support
///
/// Example:
/// ```dart
/// final text = plural('item', 5); // "5 items"
/// final textWithParams = plural('item_with_name', 5, {'name': 'John'});
/// ```
String plural(String key, num value, [Map<String, String>? namedArgs]) {
  if (activeLocale.value == null ||
      (_speaksSource() && !trExists('$key.other'))) {
    return _withArguments(key.replaceAll('{}', '$value'), namedArgs);
  }

  return key.plural(value, namedArgs: namedArgs);
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
