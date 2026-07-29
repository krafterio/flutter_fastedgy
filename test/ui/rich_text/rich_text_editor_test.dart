/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('read-only renders where the height is unbounded, as in a list', (
    tester,
  ) async {
    // Two things would throw here: the package's page block wraps its blocks
    // in a scroll view, and the editor always mounts an Overlay. Reading swaps
    // the first for a plain column and measures the second — no caller has to
    // know either.
    await pump(
      tester,
      ListView(
        children: [
          RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Premier message'),
            editable: false,
          ),
          RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Second message'),
            editable: false,
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Premier message', findRichText: true), findsOneWidget);
    expect(find.text('Second message', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'read-only takes the height of what it holds, not the space offered',
    (tester) async {
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Une ligne'),
            editable: false,
          ),
        ),
      );

      expect(tester.getSize(find.byType(RichTextEditor)).height, lessThan(200));
    },
  );

  testWidgets('read-only carries no toolbar', (tester) async {
    await pump(
      tester,
      RichTextEditor(
        features: defaultRichTextFeatures,
        editorState: stateOf('Rendu'),
        editable: false,
      ),
    );

    expect(find.byType(FloatingToolbar), findsNothing);
  });

  testWidgets('editable carries one, and fills what it is given', (
    tester,
  ) async {
    await pump(
      tester,
      RichTextEditor(
        features: defaultRichTextFeatures,
        editorState: stateOf('Saisie'),
      ),
    );

    expect(find.byType(FloatingToolbar), findsOneWidget);
    expect(find.text('Saisie', findRichText: true), findsOneWidget);
  });

  group('a field with a ceiling', () {
    /// Enough lines to stand taller than any ceiling asked of it here.
    EditorState longDraft() {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [
              for (var line = 0; line < 20; line++)
                paragraphNode(delta: Delta()..insert('Ligne $line')),
            ],
          ),
      );
      addTearDown(state.dispose);

      return state;
    }

    testWidgets('grows with what is written in it while it fits', (
      tester,
    ) async {
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Une ligne'),
            maxHeight: 140,
          ),
        ),
      );

      expect(tester.getSize(find.byType(RichTextEditor)).height, lessThan(140));
    });

    testWidgets('stops at its ceiling and scrolls past it', (tester) async {
      // Without one, a composer pinned under a thread takes a line off the
      // thread for every line typed into it, then overflows the pane.
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: longDraft(),
            maxHeight: 140,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(RichTextEditor)).height, 140);
      expect(
        find.descendant(
          of: find.byType(RichTextEditor),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });
  });

  group('a field that resets when empty', () {
    /// A heading with nothing in it — what `# ` leaves behind once the words
    /// typed after it are deleted back out.
    EditorState emptyHeading() {
      final state = EditorState(
        document: Document.blank()..insert([0], [headingNode(level: 1)]),
      );
      addTearDown(state.dispose);

      return state;
    }

    testWidgets('takes an emptied block back to the paragraph it opens on', (
      tester,
    ) async {
      final state = emptyHeading();
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: state,
          resetWhenEmpty: true,
        ),
      );

      // Whatever edit brought the field there; the field reads the document it
      // is left with, not the edit.
      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 0, ''),
      );
      await tester.pumpAndSettle();

      expect(state.document.root.children, hasLength(1));
      expect(state.document.root.children.first.type, ParagraphBlockKeys.type);
    });

    testWidgets('leaves a block that still says something alone', (
      tester,
    ) async {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [headingNode(level: 1, delta: Delta()..insert('Titre'))],
          ),
      );
      addTearDown(state.dispose);
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: state,
          resetWhenEmpty: true,
        ),
      );

      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 5, ' !'),
      );
      await tester.pumpAndSettle();

      expect(state.document.root.children.first.type, HeadingBlockKeys.type);
    });

    testWidgets('a page keeps its emptied heading, which is a heading still', (
      tester,
    ) async {
      final state = emptyHeading();
      await pump(
        tester,
        RichTextEditor(features: defaultRichTextFeatures, editorState: state),
      );

      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 0, ''),
      );
      await tester.pumpAndSettle();

      expect(state.document.root.children.first.type, HeadingBlockKeys.type);
    });
  });

  group('a field that sends on Enter', () {
    /// Puts the caret at the end of the only block, the way typing into the
    /// field would leave it.
    Future<void> pumpComposer(
      WidgetTester tester,
      EditorState state, {
      required VoidCallback onSubmit,
    }) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: state,
          onSubmit: onSubmit,
        ),
      );
      state.selection = Selection.collapsed(
        Position(
          path: [0],
          offset: state.document.root.children.first.delta!.length,
        ),
      );
      await tester.pump();
    }

    testWidgets('Enter sends rather than opening a line', (tester) async {
      final state = stateOf('Bien vu');
      var sent = 0;
      await pumpComposer(tester, state, onSubmit: () => sent++);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, 1);
      expect(state.document.root.children, hasLength(1));
    });

    testWidgets('the modifier opens the line Enter would have opened', (
      tester,
    ) async {
      final state = stateOf('Bien vu');
      var sent = 0;
      await pumpComposer(tester, state, onSubmit: () => sent++);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(sent, 0);
      expect(state.document.root.children, hasLength(2));
    });

    testWidgets('a block that keeps its own line breaks keeps Enter', (
      tester,
    ) async {
      // Enter inside a code block writes a line of code; sending the message
      // somebody is in the middle of writing is the one thing it must not do.
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [codeBlockNode(delta: Delta()..insert('print("hi")'))]),
      );
      addTearDown(state.dispose);
      var sent = 0;
      await pumpComposer(tester, state, onSubmit: () => sent++);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, 0);
    });
  });
}
