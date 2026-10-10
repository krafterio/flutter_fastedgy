/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/src/i18n/i18n.dart' as core;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

Future<BuildContext> _contextUnderI18n(WidgetTester tester) async {
  late BuildContext captured;

  rootBundle.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());

        return key == 'AssetManifest.bin'
            ? const StandardMessageCodec().encodeMessage(<String, Object?>{})
            : null;
      });
  SharedPreferences.setMockInitialValues({});

  await tester.runAsync(() async {
    await initializeI18n();
    await tester.pumpWidget(
      useI18n(
        availableLocales: const [Locale('fr')],
        child: Builder(
          builder: (context) {
            captured = context;

            return const SizedBox();
          },
        ),
      ),
    );
    await tester.idle();
  });
  await tester.pump();

  return captured;
}

void main() {
  testWidgets(
    'gives the Material and Cupertino localizations through the historical entry point',
    (tester) async {
      final delegates = FastEdgyLocalizations(await _contextUnderI18n(tester))
          .fastEdgyLocalizationDelegates;

      expect(delegates, contains(GlobalMaterialLocalizations.delegate));
      expect(delegates, contains(GlobalCupertinoLocalizations.delegate));
      expect(delegates.last, activeLocaleDelegate);
    },
  );

  testWidgets(
    'leaves the Material and Cupertino localizations out of the core ones',
    (tester) async {
      final delegates = core.FastEdgyWidgetsLocalizations(
        await _contextUnderI18n(tester),
      ).fastEdgyLocalizationDelegates;

      expect(delegates, isNot(contains(GlobalMaterialLocalizations.delegate)));
      expect(delegates, isNot(contains(GlobalCupertinoLocalizations.delegate)));
      expect(delegates.last, activeLocaleDelegate);
    },
  );
}
