/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

EditorState _stateOf(String text) => EditorState(
  document: Document.blank()..insert([0], [paragraphNode(text: text)]),
);

void main() {
  group('showRichTextPopover', () {
    testWidgets('draws with the theme the caller had, not the fallback', (
      tester,
    ) async {
      final registered = RichTextTheme.fallback.copyWith(
        floatingSurface: const BoxDecoration(color: Color(0xFF123456)),
      );

      final state = _stateOf('Une ligne');
      late BuildContext editorContext;

      await tester.pumpWidget(
        MaterialApp(
          home: ComponentTheme<RichTextTheme>(
            data: registered,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  editorContext = context;

                  return RichTextEditor(
                    editorState: state,
                    features: const RichTextFeatures([]),
                  );
                },
              ),
            ),
          ),
        ),
      );

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 5,
      );
      await tester.pumpAndSettle();

      final opened = showRichTextPopover(
        editorContext,
        state,
        state.selection!,
        builder: (context, dismiss) => const Text('carte'),
      );
      expect(opened, isTrue);
      await tester.pumpAndSettle();

      // The card lives in the root overlay, outside the subtree that carries the
      // theme. Without InheritedTheme.capture this reads the fallback instead.
      final card = tester.widget<Container>(
        find
            .ancestor(of: find.text('carte'), matching: find.byType(Container))
            .first,
      );

      expect((card.decoration as BoxDecoration).color, const Color(0xFF123456));

      state.dispose();
    });
  });
}
