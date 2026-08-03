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

  /// Le presse-papier a son propre callout sur la sélection : la surface qu'on
  /// mesure ici est celle de la barre ancrée, pas la sienne.
  final dockedSurface = find.descendant(
    of: find.byType(RichTextDockedToolbar),
    matching: find.byType(RichTextSurface),
  );

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
  });

  group('la place que la barre prend à la page', () {
    testWidgets('elle passe dessus, et la page lui garde sa place', (
      tester,
    ) async {
      final state = await pump(tester);

      final whole = tester.getSize(find.byType(RichTextEditor)).height;
      final before = tester.getSize(find.byType(AppFlowyEditor)).height;

      await select(tester, state, wholeLine());

      // Rien ne rétrécit : la barre est posée par-dessus, et ce qu'elle
      // couvrirait est réservé au pied du contenu, où le texte défile.
      expect(tester.getSize(find.byType(RichTextEditor)).height, whole);
      expect(tester.getSize(find.byType(AppFlowyEditor)).height, before);
      expect(
        tester.getRect(dockedSurface).bottom,
        closeTo(tester.getRect(find.byType(RichTextEditor)).bottom, 0.5),
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

  group('où la barre se pose', () {
    const inset = 34.0;
    const screen = Size(390, 844);

    /// L'éditeur dans une page qui défile, à la hauteur demandée : plus haute
    /// que l'écran et son pied passe dessous, ce qui colle la barre au bord.
    Future<EditorState> pumpAt(
      WidgetTester tester, {
      required double height,
      RichTextToolbarSlots slots = RichTextToolbarSlots.none,
    }) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.viewPadding = const FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);

      final state = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(delta: Delta()..insert(words))]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                height: height,
                child: RichTextEditor(
                  features: defaultRichTextFeatures,
                  editorState: state,
                  toolbarVisibility: RichTextToolbarVisibility.always,
                  toolbarSlots: slots,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      return state;
    }

    double stripBottom(WidgetTester tester) =>
        tester.getRect(find.byType(RichTextSurface)).bottom;

    double stripHeight(WidgetTester tester) =>
        tester.getSize(find.byType(RichTextSurface)).height;

    testWidgets('sur le pied de l\'éditeur quand il tient dans l\'écran', (
      tester,
    ) async {
      await pumpAt(tester, height: 400);

      expect(stripBottom(tester), closeTo(400, 0.5));
    });

    testWidgets('au bord de l\'écran quand le pied passe dessous', (
      tester,
    ) async {
      await pumpAt(tester, height: 1200);

      expect(stripBottom(tester), closeTo(screen.height, 0.5));
    });

    testWidgets('et ne garde les derniers pixels que collée au bord', (
      tester,
    ) async {
      await pumpAt(tester, height: 1200);
      final pinned = stripHeight(tester);

      await pumpAt(tester, height: 400);
      final parked = stripHeight(tester);

      // Posée sur l'éditeur, il n'y a pas de bord d'écran à laisser au système.
      expect(pinned - parked, closeTo(inset, 0.5));
    });

    testWidgets('sauf si l\'application a mis quelque chose là', (
      tester,
    ) async {
      await pumpAt(
        tester,
        height: 1200,
        slots: const RichTextToolbarSlots(below: SizedBox(height: inset)),
      );
      final held = stripHeight(tester);

      await pumpAt(tester, height: 1200);
      final bare = stripHeight(tester);

      expect(held, closeTo(bare, 0.5));
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
