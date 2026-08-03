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

  const cap = 80.0;

  Future<EditorState> pump(
    WidgetTester tester, {
    double? maxHeight = cap,
  }) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert('Une ligne'))]),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
              maxHeight: maxHeight,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return state;
  }

  /// Écrit assez de lignes pour dépasser la fenêtre, curseur sur la dernière.
  Future<void> fill(
    WidgetTester tester,
    EditorState state, {
    int lines = 12,
  }) async {
    final transaction = state.transaction;

    for (var line = 0; line < lines; line += 1) {
      transaction.insertNode([
        line + 1,
      ], paragraphNode(delta: Delta()..insert('Ligne $line')));
    }

    await state.apply(transaction);
    state.selection = Selection.collapsed(Position(path: [lines], offset: 0));
    await tester.pumpAndSettle();
  }

  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<RichTextEditorState>(find.byType(RichTextEditor))
      .scrollController
      .scrollController
      .position;

  /// Le curseur est-il dans la fenêtre du champ — la seule chose qui compte,
  /// le reste n'étant que la façon d'y arriver.
  void expectCaretInWindow(WidgetTester tester, EditorState state) {
    final window = tester.getRect(find.byType(RichTextEditor));
    final caret = state.selectionRects().first;

    expect(caret.top, greaterThanOrEqualTo(window.top - 1));
    expect(caret.bottom, lessThanOrEqualTo(window.bottom + 1));
  }

  group('un champ qui a sa propre hauteur', () {
    testWidgets('suit le curseur quand une ligne le pousse hors de vue', (
      tester,
    ) async {
      final state = await pump(tester);

      expect(positionOf(tester).pixels, 0);

      await fill(tester, state);

      final position = positionOf(tester);

      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, greaterThan(0));
      expectCaretInWindow(tester, state);
    });

    testWidgets('et le ramène quand il remonte', (tester) async {
      final state = await pump(tester);
      await fill(tester, state);

      final scrolled = positionOf(tester).pixels;

      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await tester.pumpAndSettle();

      expect(positionOf(tester).pixels, lessThan(scrolled));
      expectCaretInWindow(tester, state);
    });
  });

  group('la barre ancrée sur un champ qui grandit', () {
    /// Un composeur : posé en bas de l'écran, haut d'une ligne, et qui grandit
    /// jusqu'à un plafond.
    Future<EditorState> pumpComposer(
      WidgetTester tester, {
      bool toolbar = true,
      RichTextToolbarEdge edge = RichTextToolbarEdge.bottom,
    }) async {
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(delta: Delta()..insert('Test'))]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Spacer(),
                Container(
                  // Le plafond est celui des mots, porté par l'éditeur : le
                  // champ, lui, grandit de la barre quand elle se lève.
                  constraints: const BoxConstraints(minHeight: 48),
                  child: RichTextEditor(
                    features: defaultRichTextFeatures,
                    editorState: state,
                    maxHeight: 144,
                    toolbar: toolbar,
                    toolbarEdge: edge,
                    menuItems: const [],
                    toolbarVisibility: RichTextToolbarVisibility.selection,
                    actions: RichTextActions.marks,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      return state;
    }

    testWidgets('ne se pose pas sur la ligne qu\'on écrit', (tester) async {
      final state = await pumpComposer(tester);

      final before = tester.getRect(find.text('Test', findRichText: true));

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pumpAndSettle();

      final text = tester.getRect(find.text('Test', findRichText: true));
      final strip = tester.getRect(find.byType(RichTextActionBar));

      // Le champ garde la hauteur de la barre au pied de son contenu, donc il
      // grandit et le texte remonte d'autant.
      expect(text.top, lessThan(before.top));
      expect(text.bottom, lessThanOrEqualTo(strip.top));
    });

    testWidgets('reste au pied de la fenêtre quand le contenu la dépasse', (
      tester,
    ) async {
      final state = await pumpComposer(tester);

      final transaction = state.transaction;

      for (var line = 0; line < 6; line += 1) {
        transaction.insertNode([
          line + 1,
        ], paragraphNode(delta: Delta()..insert('Ligne \$line')));
      }

      await state.apply(transaction);
      await tester.pumpAndSettle();

      final before = tester.getRect(find.byType(RichTextEditor));

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(RichTextEditor));
      final strip = tester.getRect(find.byType(RichTextActionBar));

      // Le plafond est celui des mots : ce qu'on peut lire du champ ne change
      // pas quand la barre se lève, c'est le champ qui grandit d'autant.
      final surface = tester.getRect(find.byType(RichTextSurface).first);

      expect(field.height - before.height, closeTo(surface.height, 1));

      // Le champ plafonné met ses blocs dans un scroll view, et une barre à
      // l'intérieur se posait au pied de tout ce qui est écrit : hors du champ,
      // coupée par son bord, dès qu'il y avait plus d'une ligne.
      expect(strip.bottom, closeTo(field.bottom, 1));

      // Et la fenêtre où défilent les blocs s'arrête où la barre commence : le
      // champ ne peut pas grandir pour lui faire de la place, donc c'est le
      // plafond qui la lui donne.
      expect(state.selectionRects().first.bottom, lessThanOrEqualTo(strip.top));
    });

    /// De combien le menu de sélection est décalé par rapport aux mots qu'il
    /// désigne — ce qui ne doit dépendre que d'eux.
    Future<double> menuOffset(
      WidgetTester tester, {
      bool toolbar = true,
    }) async {
      final state = await pumpComposer(tester, toolbar: toolbar);

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pumpAndSettle();

      return tester.getRect(find.text('Copy')).top -
          tester.getRect(find.text('Test', findRichText: true)).top;
    }

    testWidgets('ancrée en tête, elle laisse le pied du champ où il est', (
      tester,
    ) async {
      final state = await pumpComposer(tester, edge: RichTextToolbarEdge.top);

      final before = tester.getRect(find.byType(RichTextEditor));

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(RichTextEditor));
      final strip = tester.getRect(find.byType(RichTextActionBar));

      // Le champ grandit par le haut, donc son pied ne bouge pas : rien de ce
      // qui est écrit ne saute sous le pouce qui allait le toucher.
      expect(field.bottom, closeTo(before.bottom, 1));
      expect(strip.top, closeTo(field.top, 1));
      expect(
        state.selectionRects().first.top,
        greaterThanOrEqualTo(strip.bottom),
      );
    });

    testWidgets('et le menu de sélection passe sous les mots pour l\'éviter', (
      tester,
    ) async {
      final state = await pumpComposer(tester, edge: RichTextToolbarEdge.top);

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pumpAndSettle();

      final strip = tester.getRect(find.byType(RichTextActionBar));
      final menu = tester.getRect(find.text('Copy'));

      // Au-dessus des mots il n'y a plus que la barre, et le menu s'y posait.
      expect(menu.top, greaterThanOrEqualTo(strip.bottom));
    });

    testWidgets('et le menu de sélection suit les mots qui remontent', (
      tester,
    ) async {
      // Le paquet ancre ce menu une fois, sur la frame où il le lève, et les
      // mots bougent ensuite : la barre prend sa place au pied du contenu et
      // tout ce qui est au-dessus remonte d'autant. Le menu restait où les mots
      // étaient.
      expect(
        await menuOffset(tester),
        closeTo(await menuOffset(tester, toolbar: false), 1),
      );
    });
  });
}
