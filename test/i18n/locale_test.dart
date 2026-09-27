/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _serve(Map<String, Map<String, String>> bundle) {
  rootBundle.clear();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final payload = bundle[utf8.decode(message!.buffer.asUint8List())];

        return payload == null
            ? null
            : ByteData.sublistView(utf8.encode(jsonEncode(payload)));
      });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required String? locale,
  Map<String, Map<String, String>> bundle = const {},
  String Function() text = _empty,
}) async {
  _serve(bundle);
  SharedPreferences.setMockInitialValues({'locale': ?locale});

  await tester.runAsync(() async {
    await initializeI18n();
    await tester.pumpWidget(
      useI18n(
        supportedLocales: const [Locale('fr'), Locale('en')],
        fallbackLocale: const Locale('en'),
        sourceLocale: const Locale('fr'),
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

    testWidgets('a key translated in the source language is translated', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        locale: 'fr',
        bundle: {
          'packages/flutter_fastedgy/assets/translations/fr.json': {
            'Copy': 'Copier',
          },
        },
        text: () => t('Copy'),
      );

      expect(find.text('Copier'), findsOneWidget);
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
