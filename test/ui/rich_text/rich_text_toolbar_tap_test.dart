/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  EditorState stateOf(String text) => EditorState(
    document: Document.blank()
      ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
  );

  /// The editor as a page mounts it, with a selection over the words — which is
  /// what puts the toolbar up in the first place.
  Future<EditorState> pumpSelected(WidgetTester tester, String text) async {
    final state = stateOf(text);
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

    state.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: text.length,
    );
    await tester.pumpAndSettle();

    return state;
  }

  group('taper la barre depuis l\'éditeur', () {
    testWidgets('la barre est là dès qu\'il y a une sélection', (tester) async {
      await pumpSelected(tester, 'Mars Attack');

      expect(find.byType(RichTextActionBar), findsOneWidget);
    });

    testWidgets('un bouton applique bien sa marque au texte sélectionné', (
      tester,
    ) async {
      final state = await pumpSelected(tester, 'Mars Attack');
      final bold = RichTextActions.standard.firstWhere(
        (action) => action.id == 'bold',
      );

      await tester.tap(find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.bold]));
      await tester.pumpAndSettle();

      expect(bold.isActive(state), isTrue);
    });

    testWidgets('la barre disparaît avec la sélection', (tester) async {
      final state = await pumpSelected(tester, 'Mars Attack');

      state.selection = null;
      await tester.pumpAndSettle();

      expect(find.byType(RichTextActionBar), findsNothing);
    });

    testWidgets('un bouton de bloc change bien le bloc', (tester) async {
      final state = await pumpSelected(tester, 'Courses');

      await tester.tap(
        find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.bulletedList]),
      );
      await tester.pumpAndSettle();

      expect(state.getNodeAtPath([0])?.type, BulletedListBlockKeys.type);
    });
  });

  group('faire glisser la barre', () {
    Future<ScrollPosition> pumpNarrow(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpSelected(tester, 'Mars Attack');

      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(RichTextActionBar),
              matching: find.byType(Scrollable),
            ),
          )
          .position;

      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'la barre tient à l\'écran, il n\'y a rien à faire glisser',
      );

      return position;
    }

    testWidgets('elle suit le doigt, même parti d\'un bouton', (tester) async {
      final position = await pumpNarrow(tester);

      await tester.drag(find.byType(Icon).first, const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));
    });

    testWidgets('elle s\'arrête au bout plutôt que de continuer', (
      tester,
    ) async {
      final position = await pumpNarrow(tester);

      await tester.drag(find.byType(Icon).first, const Offset(-4000, 0));
      await tester.pumpAndSettle();

      expect(position.pixels, position.maxScrollExtent);
    });

    testWidgets('glisser ne déclenche pas le bouton touché au départ', (
      tester,
    ) async {
      final state = await pumpSelected(tester, 'Mars Attack');
      final bold = RichTextActions.standard.firstWhere(
        (action) => action.id == 'bold',
      );

      await tester.drag(
        find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.bold]),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      expect(bold.isActive(state), isFalse);
    });
  });
}
