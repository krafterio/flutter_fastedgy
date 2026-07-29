/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/ui.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  EditorState stateOf(String text) {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
    );
    addTearDown(state.dispose);

    return state;
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  testWidgets('reads at the width the page was written at, given the room', (
    tester,
  ) async {
    // A surface wider than the column, so what bounds the blocks is the
    // column's own constraint rather than the window.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, DocumentView(editorState: stateOf('Une description')));

    expect(find.text('Une description', findRichText: true), findsOneWidget);
    expect(
      tester.getSize(find.byType(RichTextView)).width,
      DocumentLayout.standard.contentWidth,
    );
  });

  testWidgets('narrows with the page rather than overflowing it', (
    tester,
  ) async {
    const width = 400.0;

    await pump(
      tester,
      SizedBox(
        width: width,
        child: DocumentView(editorState: stateOf('À l’étroit')),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(RichTextView)).width,
      width - 2 * DocumentLayout.standard.horizontalPadding,
    );
  });

  testWidgets('carries a header and a footer on that same column', (
    tester,
  ) async {
    await pump(
      tester,
      DocumentView(
        editorState: stateOf('Corps'),
        header: const Text('En-tête'),
        footer: const Text('Pied'),
      ),
    );

    expect(find.text('En-tête'), findsOneWidget);
    expect(find.text('Pied'), findsOneWidget);
  });

  testWidgets('scrolls no more than what it is put in', (tester) async {
    await pump(
      tester,
      ListView(
        children: [DocumentView(editorState: stateOf('Dans une liste'))],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Dans une liste', findRichText: true), findsOneWidget);
  });
}
