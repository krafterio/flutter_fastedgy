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

  const words = 'Mars Attack';

  RichTextAction actionOf(String id) =>
      RichTextActions.standard.firstWhere((action) => action.id == id);

  Selection wholeLine() =>
      Selection.single(path: [0], startOffset: 0, endOffset: words.length);

  Selection caret() =>
      Selection.collapsed(Position(path: [0], offset: words.length));

  /// The page as a phone mounts it — a touch platform docks the strip, which is
  /// the only placement that gets to outlast a selection.
  Future<EditorState> pump(
    WidgetTester tester, {
    RichTextToolbarVisibility? visibility,
    RichTextToolbarSlots slots = RichTextToolbarSlots.none,
  }) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(words))]),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: state,
            scrollable: true,
            toolbarVisibility: visibility,
            toolbarSlots: slots,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return state;
  }

  Future<void> select(
    WidgetTester tester,
    EditorState state,
    Selection? to,
  ) async {
    state.selection = to;
    await tester.pumpAndSettle();
  }

  final bar = find.byType(RichTextActionBar);

  group('combien de temps la barre ancrée reste', () {
    testWidgets('par défaut, tant que le curseur est dans le document', (
      tester,
    ) async {
      final state = await pump(tester);

      await select(tester, state, wholeLine());
      expect(bar, findsOneWidget);

      await select(tester, state, caret());
      expect(bar, findsOneWidget);

      await select(tester, state, null);
      expect(bar, findsNothing);
    });

    testWidgets('annuler ne la fait plus disparaître', (tester) async {
      final state = await pump(tester);

      await select(tester, state, wholeLine());
      await actionOf('bold').run(state);
      await tester.pumpAndSettle();

      await actionOf('undo').run(state);
      await tester.pumpAndSettle();

      expect(bar, findsOneWidget);
    });

    testWidgets('en mode sélection, elle part avec les mots choisis', (
      tester,
    ) async {
      final state = await pump(
        tester,
        visibility: RichTextToolbarVisibility.selection,
      );

      await select(tester, state, wholeLine());
      expect(bar, findsOneWidget);

      await select(tester, state, caret());
      expect(bar, findsNothing);
    });

    testWidgets('en mode toujours, elle tient sans rien de sélectionné', (
      tester,
    ) async {
      final state = await pump(
        tester,
        visibility: RichTextToolbarVisibility.always,
      );

      expect(bar, findsOneWidget);

      await select(tester, state, null);
      expect(bar, findsOneWidget);
    });

    testWidgets('debout sans curseur, elle n\'offre que ce qui s\'en passe', (
      tester,
    ) async {
      final state = await pump(
        tester,
        visibility: RichTextToolbarVisibility.always,
      );

      await select(tester, state, wholeLine());
      await actionOf('bold').run(state);
      await select(tester, state, null);

      expect(actionOf('bold').isEnabled(state), isFalse);
      expect(actionOf('bulleted_list').isEnabled(state), isFalse);
      expect(actionOf('undo').isEnabled(state), isTrue);
    });
  });

  group('la place laissée à l\'application', () {
    const slots = RichTextToolbarSlots(
      leading: Text('tête'),
      trailing: Text('queue'),
      above: Text('au-dessus'),
      below: SizedBox(height: 64, child: Text('en dessous')),
    );

    testWidgets('les quatre sont posés', (tester) async {
      await pump(
        tester,
        visibility: RichTextToolbarVisibility.always,
        slots: slots,
      );

      for (final label in ['tête', 'queue', 'au-dessus', 'en dessous']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('les deux horizontaux voyagent avec les boutons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = await pump(
        tester,
        visibility: RichTextToolbarVisibility.always,
        slots: slots,
      );

      await select(tester, state, wholeLine());

      final before = tester.getTopLeft(find.text('tête')).dx;

      await tester.drag(find.byType(Icon).first, const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('tête')).dx, lessThan(before));
    });

    testWidgets('la bande du bas prend le bord à sa charge', (tester) async {
      const inset = 34.0;

      Future<double> heightWith(RichTextToolbarSlots given) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding.zero;
        tester.view.viewPadding = const FakeViewPadding(bottom: inset);
        addTearDown(tester.view.reset);

        await pump(
          tester,
          visibility: RichTextToolbarVisibility.always,
          slots: given,
        );

        return tester.getSize(find.byType(RichTextSurface)).height;
      }

      final bare = await heightWith(RichTextToolbarSlots.none);
      final held = await heightWith(
        const RichTextToolbarSlots(below: SizedBox(height: inset)),
      );

      expect(held, bare);
    });
  });

  group('la place que la barre prend à la page', () {
    testWidgets('elle est posée à côté de l\'éditeur, pas dessus', (
      tester,
    ) async {
      final state = await pump(tester);

      final whole = tester.getSize(find.byType(RichTextEditor)).height;
      final before = tester.getSize(find.byType(AppFlowyEditor)).height;

      await select(tester, state, wholeLine());

      final strip = tester.getSize(find.byType(RichTextSurface)).height;

      expect(tester.getSize(find.byType(RichTextEditor)).height, whole);
      expect(
        tester.getSize(find.byType(AppFlowyEditor)).height,
        before - strip,
      );
      expect(
        tester.getBottomLeft(find.byType(AppFlowyEditor)).dy,
        tester.getTopLeft(find.byType(RichTextSurface)).dy,
      );
    });

    testWidgets('le contenu garde une marge au-dessus de la barre', (
      tester,
    ) async {
      final gap = RichTextToolbarTheme.from(
        RichTextTheme.fallback,
        docked: true,
      ).contentGap;

      expect(gap, greaterThan(0), reason: 'une marge par défaut, pas zéro');

      await pump(tester, visibility: RichTextToolbarVisibility.always);

      final text = find.text(words, findRichText: true);

      expect(
        tester.getTopLeft(find.byType(RichTextSurface)).dy -
            tester.getBottomLeft(text).dy,
        greaterThanOrEqualTo(gap),
      );
    });

    testWidgets('ce qu\'on met sous le contenu est au pied de ce qui défile', (
      tester,
    ) async {
      await pump(
        tester,
        visibility: RichTextToolbarVisibility.always,
        slots: const RichTextToolbarSlots(
          underContent: SizedBox(height: 40, child: Text('marge')),
        ),
      );

      expect(
        tester.getTopLeft(find.text('marge')).dy,
        greaterThan(tester.getTopLeft(find.text(words, findRichText: true)).dy),
      );
      expect(
        tester.getBottomLeft(find.text('marge')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(RichTextSurface)).dy),
      );
    });
  });

  group('ce que la barre reprend avant d\'agir', () {
    testWidgets('le curseur d\'avant l\'appui, pas celui d\'après', (
      tester,
    ) async {
      final state = await pump(tester);

      await select(tester, state, wholeLine());

      await tester.tap(find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.bold]));
      await tester.pumpAndSettle();

      expect(actionOf('bold').isActive(state), isTrue);
      expect(state.selection, wholeLine());
    });
  });
}
