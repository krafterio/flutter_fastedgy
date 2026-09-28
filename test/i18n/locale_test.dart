/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _serve(Map<String, Map<String, String>> bundle) {
  rootBundle.clear();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());

        if (key == 'AssetManifest.bin') {
          return const StandardMessageCodec().encodeMessage({
            for (final asset in bundle.keys) asset: <Object?>[],
          });
        }

        final payload = bundle[key];

        return payload == null
            ? null
            : ByteData.sublistView(utf8.encode(jsonEncode(payload)));
      });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required String? locale,
  Locale? appLocale,
  Locale? sourceLocale = const Locale('fr'),
  Map<String, Locale> packageSourceLocales = const {},
  Map<String, Map<String, String>> bundle = const {},
  String Function() text = _empty,
}) async {
  _serve(bundle);
  SharedPreferences.setMockInitialValues({'locale': ?locale});

  await tester.runAsync(() async {
    await initializeI18n();
    await tester.pumpWidget(
      useI18n(
        availableLocales: const [Locale('fr'), Locale('en')],
        locale: appLocale,
        fallbackLocale: const Locale('en'),
        sourceLocale: sourceLocale,
        packageSourceLocales: packageSourceLocales,
        child: Builder(
          builder: (context) => WidgetsApp(
            color: const Color(0xFF000000),
            localizationsDelegates: context.fastEdgyLocalizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            builder: (context, _) => Text(text()),
          ),
        ),
      ),
    );
    await tester.idle();
  });
  await tester.pumpAndSettle();
}

String _empty() => '';

class _Handler extends RequestInterceptorHandler {
  RequestOptions? options;

  @override
  void next(RequestOptions requestOptions) {
    options = requestOptions;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('source locale', () {
    testWidgets('records the locale the application displays', (tester) async {
      await _pumpApp(
        tester,
        locale: 'en',
        bundle: {},
        text: () => t('Bonjour'),
      );

      expect(activeLocale.value, const Locale('en'));
    });

    testWidgets('tells its listeners when the language changes', (
      tester,
    ) async {
      await _pumpApp(tester, locale: 'en');
      final heard = <Locale?>[];
      void listener() => heard.add(activeLocale.value);
      activeLocale.addListener(listener);
      addTearDown(() => activeLocale.removeListener(listener));

      await tester.runAsync(
        () => tester
            .element(find.byType(WidgetsApp))
            .setLocale(const Locale('fr')),
      );
      await tester.pumpAndSettle();

      expect(heard, [const Locale('fr')]);
    });

    testWidgets(
      'a key with no translation is the text in the source language, never the fallback',
      (tester) async {
        await _pumpApp(
          tester,
          locale: 'fr',
          bundle: {
            'assets/translations/en.json': {'Bonjour {name}': 'Hello {name}'},
          },
          text: () => t('Bonjour {name}', {'name': 'Léa'}),
        );

        expect(find.text('Bonjour Léa'), findsOneWidget);
      },
    );

    testWidgets(
      'a plural with no forms in the source language shows its key with the number',
      (tester) async {
        await _pumpApp(
          tester,
          locale: 'fr',
          text: () => plural('{} membres', 4),
        );

        expect(find.text('4 membres'), findsOneWidget);
      },
    );

    testWidgets(
      'the keys are in the fallback language when no source language is given',
      (tester) async {
        await _pumpApp(
          tester,
          locale: 'en',
          sourceLocale: null,
          text: () => plural('{} members', 4),
        );

        expect(find.text('4 members'), findsOneWidget);
      },
    );

    testWidgets('a key translated in the source language is translated', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'fr',
        bundle: {
          'assets/translations/fr.json': {'Bonjour': 'Salut'},
        },
        text: () => t('Bonjour'),
      );

      expect(find.text('Salut'), findsOneWidget);
    });

    testWidgets('another language reads its own translation', (tester) async {
      await _pumpApp(
        tester,
        locale: 'en',
        bundle: {
          'assets/translations/en.json': {'Bonjour {name}': 'Hello {name}'},
        },
        text: () => t('Bonjour {name}', {'name': 'Léa'}),
      );

      expect(find.text('Hello Léa'), findsOneWidget);
    });

    testWidgets('a key of the application never takes a word of the package', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'fr',
        bundle: {
          'packages/flutter_fastedgy/assets/translations/fr.json': {
            'Location': 'Emplacement',
          },
          'assets/translations/en.json': {'Location': 'Rental'},
        },
        text: () => t('Location'),
      );

      expect(find.text('Location'), findsOneWidget);
    });
  });

  group('words of the package', () {
    const package = 'packages/flutter_fastedgy/assets/translations/fr.json';

    testWidgets('come from every package the asset manifest lists', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'fr',
        bundle: {
          'packages/other_package/assets/translations/fr.json': {
            'Share': 'Partager',
          },
        },
        text: () => t('Share'),
      );

      expect(find.text('Partager'), findsOneWidget);
    });

    testWidgets('follow the source language the application gives a package', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'en',
        packageSourceLocales: const {'other_package': Locale('de')},
        bundle: {
          'packages/other_package/assets/translations/en.json': {
            'Teilen': 'Share',
          },
        },
        text: () => t('Teilen'),
      );

      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('speak the displayed language from the package catalog', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'fr',
        bundle: {
          package: {'Copy {name}': 'Copier {name}'},
        },
        text: () => t('Copy {name}', {'name': 'le lien'}),
      );

      expect(find.text('Copier le lien'), findsOneWidget);
    });

    testWidgets('are their English key in English, with no English catalog', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'en',
        bundle: {
          package: {'Copy': 'Copier'},
        },
        text: () => t('Copy'),
      );

      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('show their English where the package has no translation', (
      tester,
    ) async {
      await _pumpApp(tester, locale: 'fr', text: () => t('Paste'));

      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('take the wording the application gives them', (tester) async {
      await _pumpApp(
        tester,
        locale: 'fr',
        bundle: {
          package: {'Copy': 'Copier'},
          'assets/translations/fr.json': {'Copy': 'Dupliquer'},
        },
        text: () => t('Copy'),
      );

      expect(find.text('Dupliquer'), findsOneWidget);
    });
  });

  group('translatable string', () {
    testWidgets(
      'declared once, renders in the language displayed at each read',
      (tester) async {
        final label = ts('Bonjour {name}', {'name': 'Léa'});
        await _pumpApp(
          tester,
          locale: 'fr',
          bundle: {
            'assets/translations/en.json': {'Bonjour {name}': 'Hello {name}'},
          },
        );
        expect(label.render(), 'Bonjour Léa');

        await tester.runAsync(
          () => chooseLocale(
            tester.element(find.byType(WidgetsApp)),
            const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect('$label', 'Hello Léa');
      },
    );
  });

  group('device locale', () {
    void speak(WidgetTester tester, Locale device) {
      tester.platformDispatcher.localeTestValue = device;
      tester.platformDispatcher.localesTestValue = [device];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    BuildContext app(WidgetTester tester) =>
        tester.element(find.byType(WidgetsApp));

    testWidgets('starts in the language of the device when none was chosen', (
      tester,
    ) async {
      speak(tester, const Locale('fr', 'FR'));

      await _pumpApp(tester, locale: null);

      expect(activeLocale.value, const Locale('fr'));
    });

    testWidgets(
      'starts in the fallback when the device speaks another language',
      (tester) async {
        speak(tester, const Locale('it', 'IT'));

        await _pumpApp(tester, locale: null);

        expect(activeLocale.value, const Locale('en'));
      },
    );

    testWidgets(
      'follows the device when its language changes and none was chosen',
      (tester) async {
        speak(tester, const Locale('fr', 'FR'));
        await _pumpApp(tester, locale: null);

        speak(tester, const Locale('en', 'GB'));
        await settle(tester);

        expect(activeLocale.value, const Locale('en'));
        expect(chosenLocale.value, isNull);
      },
    );

    testWidgets('keeps a language chosen in the app when the device changes', (
      tester,
    ) async {
      speak(tester, const Locale('en', 'GB'));
      await _pumpApp(tester, locale: 'fr');

      speak(tester, const Locale('en', 'US'));
      await settle(tester);

      expect(activeLocale.value, const Locale('fr'));
    });

    testWidgets(
      'keeps a language chosen during the session when the device changes',
      (tester) async {
        speak(tester, const Locale('fr', 'FR'));
        await _pumpApp(tester, locale: null);

        await tester.runAsync(
          () => chooseLocale(app(tester), const Locale('en')),
        );
        await settle(tester);
        speak(tester, const Locale('fr', 'CA'));
        await settle(tester);

        expect(activeLocale.value, const Locale('en'));
        expect(chosenLocale.value, const Locale('en'));
      },
    );

    testWidgets('starts in the language the app gives, over the device', (
      tester,
    ) async {
      speak(tester, const Locale('fr', 'FR'));

      await _pumpApp(tester, locale: null, appLocale: const Locale('en'));

      expect(activeLocale.value, const Locale('en'));
      expect(chosenLocale.value, const Locale('en'));
    });

    testWidgets(
      'the language the app gives wins over the one chosen on the device',
      (tester) async {
        speak(tester, const Locale('fr', 'FR'));
        await _pumpApp(tester, locale: 'fr', appLocale: const Locale('en'));

        await settle(tester);

        expect(activeLocale.value, const Locale('en'));
      },
    );

    testWidgets('ignores a language the app gives but does not offer', (
      tester,
    ) async {
      speak(tester, const Locale('fr', 'FR'));

      await _pumpApp(tester, locale: null, appLocale: const Locale('it'));

      expect(activeLocale.value, const Locale('fr'));
      expect(chosenLocale.value, isNull);
    });

    testWidgets('followDeviceLocale drops the language chosen in the app', (
      tester,
    ) async {
      speak(tester, const Locale('en', 'GB'));
      await _pumpApp(tester, locale: 'fr');

      await tester.runAsync(() => followDeviceLocale(app(tester)));
      await settle(tester);

      expect(activeLocale.value, const Locale('en'));
      expect(chosenLocale.value, isNull);
    });
  });

  group('intl default locale', () {
    void speak(WidgetTester tester, Locale device) {
      tester.platformDispatcher.localeTestValue = device;
      tester.platformDispatcher.localesTestValue = [device];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }

    testWidgets(
      'formats in the language displayed, with the region of the device',
      (tester) async {
        speak(tester, const Locale('fr', 'GB'));

        await _pumpApp(tester, locale: 'en');

        expect(Intl.defaultLocale, 'en_GB');
        expect(
          DateFormat.MMMMd().format(DateTime(2026, 9, 27)),
          '27 September',
        );
      },
    );

    testWidgets(
      'formats in the language alone when the region does not fit it',
      (tester) async {
        speak(tester, const Locale('en', 'ZZ'));

        await _pumpApp(tester, locale: 'fr');

        expect(Intl.defaultLocale, 'fr');
        expect(
          DateFormat.MMMMd().format(DateTime(2026, 9, 27)),
          '27 septembre',
        );
      },
    );
  });

  group('LocaleInterceptor', () {
    testWidgets('sends the displayed locale as Accept-Language', (
      tester,
    ) async {
      await _pumpApp(tester, locale: 'en');
      final handler = _Handler();

      LocaleInterceptor().onRequest(RequestOptions(path: '/test'), handler);

      expect(handler.options!.headers['Accept-Language'], 'en');
    });

    testWidgets('keeps the Accept-Language a request already carries', (
      tester,
    ) async {
      await _pumpApp(tester, locale: 'en');
      final handler = _Handler();

      LocaleInterceptor().onRequest(
        RequestOptions(path: '/test', headers: {'Accept-Language': 'it'}),
        handler,
      );

      expect(handler.options!.headers['Accept-Language'], 'it');
    });
  });
}
