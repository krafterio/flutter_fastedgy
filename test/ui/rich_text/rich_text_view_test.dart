/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  EditorState stateOf(List<Node> nodes) {
    final state = EditorState(document: Document.blank()..insert([0], nodes));
    addTearDown(state.dispose);

    return state;
  }

  EditorState textOf(String text) =>
      stateOf([paragraphNode(delta: Delta()..insert(text))]);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  testWidgets('renders down a list, where the height is unbounded', (
    tester,
  ) async {
    await pump(
      tester,
      ListView(
        children: [
          RichTextView(
            editorState: textOf('Premier message'),
            features: defaultRichTextFeatures,
          ),
          RichTextView(
            editorState: textOf('Second message'),
            features: defaultRichTextFeatures,
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Premier message', findRichText: true), findsOneWidget);
    expect(find.text('Second message', findRichText: true), findsOneWidget);
  });

  testWidgets('mounts none of the editor', (tester) async {
    await pump(
      tester,
      RichTextView(
        editorState: textOf('Rendu'),
        features: defaultRichTextFeatures,
      ),
    );

    // The whole point: a provider and a column of blocks, not a focus scope, an
    // overlay and three service layers per message.
    expect(find.byType(AppFlowyEditor), findsNothing);
    expect(find.byType(FloatingToolbar), findsNothing);
    expect(find.text('Rendu', findRichText: true), findsOneWidget);
  });

  testWidgets('renders the blocks the editor writes, features included', (
    tester,
  ) async {
    await pump(
      tester,
      RichTextView(
        features: defaultRichTextFeatures,
        editorState: stateOf([
          paragraphNode(delta: Delta()..insert('Avant')),
          codeBlockNode(
            delta: Delta()..insert('print("hi")'),
            language: 'python',
          ),
        ]),
      ),
    );

    expect(find.byType(CodeBlockComponentWidget), findsOneWidget);
    expect(find.text('Avant', findRichText: true), findsOneWidget);
  });

  testWidgets('takes the height of what it holds', (tester) async {
    await pump(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: RichTextView(
          editorState: textOf('Une ligne'),
          features: defaultRichTextFeatures,
        ),
      ),
    );

    expect(tester.getSize(find.byType(RichTextView)).height, lessThan(120));
  });
}
