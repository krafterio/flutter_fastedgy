/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(() {
    resetUiTestServices();
    forceShowBlockAction = false;
  });

  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;

    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<EditorState> pumpEditor(WidgetTester tester, String text) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: state,
            scrollable: true,
          ),
        ),
      ),
    );
    await tester.pump();

    return state;
  }

  String textOf(EditorState state) =>
      state.getNodeAtPath([0])?.delta?.toPlainText() ?? '';

  void caretAtEnd(EditorState state) {
    state.selection = Selection.collapsed(
      Position(path: [0], offset: textOf(state).length),
    );
  }

  Future<void> type(WidgetTester tester, EditorState state, String text) async {
    final events = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .characterShortcutEvents;

    for (final character in text.split('')) {
      var handled = false;

      for (final event in events.where(
        (event) => event.character == character,
      )) {
        if (handled = await event.handler(state)) {
          break;
        }
      }

      if (!handled) {
        await state.insertTextAtPosition(
          character,
          position: state.selection!.start,
        );
      }

      await tester.pumpAndSettle();
    }
  }

  Finder rowNamed(String label) =>
      find.descendant(of: find.byType(Scrollbar), matching: find.text(label));

  group('la liste des blocs au doigt', () {
    // Upstream answers false on a touch platform before doing anything, so the
    // character was typed and nothing was ever offered.
    testWidgets('« / » ouvre une carte sur le curseur, pas une feuille', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, '');
        caretAtEnd(state);

        await type(tester, state, '/');

        expect(rowNamed(t('Quote')), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
      });
    });

    testWidgets('elle se réduit à mesure qu\'on tape, sans fermer le clavier', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, '');
        caretAtEnd(state);

        await type(tester, state, '/');
        expect(rowNamed(t('Quote')), findsOneWidget);

        await type(tester, state, 'quo');

        expect(textOf(state), '/quo');
        expect(rowNamed(t('Quote')), findsOneWidget);
        expect(rowNamed(t('Text')), findsNothing);
      });
    });

    testWidgets('choisir applique le bloc et reprend ce qui a été tapé', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, '');
        caretAtEnd(state);

        await type(tester, state, '/quo');
        await tester.tap(rowNamed(t('Quote')));
        await tester.pumpAndSettle();

        expect(state.getNodeAtPath([0])?.type, QuoteBlockKeys.type);
        expect(textOf(state), isEmpty);
      });
    });

    testWidgets('la ligne courante porte les couleurs du thème', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, '');
        caretAtEnd(state);

        await type(tester, state, '/');

        final style = RichTextStyle.slashMenu(RichTextTheme.fallback);
        final colours = tester
            .widgetList<EditorSvg>(
              find.descendant(
                of: find.byType(Scrollbar),
                matching: find.byType(EditorSvg),
              ),
            )
            .map((svg) => svg.color)
            .toSet();

        expect(colours, contains(style.selectionMenuItemSelectedIconColor));
        expect(colours, contains(style.selectionMenuItemIconColor));
        expect(
          colours,
          isNot(
            contains(
              SelectionMenuStyle.light.selectionMenuItemSelectedIconColor,
            ),
          ),
        );
      });
    });

    testWidgets('effacer le « / » referme la carte', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, '');
        caretAtEnd(state);

        await type(tester, state, '/');
        expect(rowNamed(t('Quote')), findsOneWidget);

        await state.apply(
          state.transaction..deleteText(state.getNodeAtPath([0])!, 0, 1),
        );
        await tester.pumpAndSettle();

        expect(rowNamed(t('Quote')), findsNothing);
      });
    });

    testWidgets('un « / » au milieu d\'un mot reste un « / »', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, '12');
        caretAtEnd(state);

        await type(tester, state, '/');

        expect(textOf(state), '12/');
        expect(rowNamed(t('Quote')), findsNothing);
      });
    });

    testWidgets('le bouton de la barre ouvre la même carte, sans rien écrire', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpEditor(tester, 'Un');
        caretAtEnd(state);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.slash]),
        );
        await tester.pumpAndSettle();

        expect(rowNamed(t('Quote')), findsOneWidget);
        expect(textOf(state), 'Un');
      });
    });
  });

  group('la liste des blocs au pointeur', () {
    testWidgets('reste celle de l\'éditeur, et la barre n\'a pas le bouton', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final state = await pumpEditor(tester, '');
        caretAtEnd(state);

        await type(tester, state, '/');

        expect(
          find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.slash]),
          findsNothing,
        );
        expect(textOf(state), '/');
      });
    });
  });
}
