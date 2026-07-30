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
}
