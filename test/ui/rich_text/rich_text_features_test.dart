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

  EditorState stateOf(String text) {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
    );
    addTearDown(state.dispose);

    return state;
  }

  group('narrowing the set', () {
    test('without drops a feature and everything it contributes', () {
      const full = defaultRichTextFeatures;
      final prose = full.without<CodeBlockFeature>();

      expect(full.features.whereType<CodeBlockFeature>(), isNotEmpty);
      expect(prose.features.whereType<CodeBlockFeature>(), isEmpty);
      // Its block, its "/" entry and its markdown both ways go with it.
      expect(prose.builders, isNot(contains(CodeBlockKeys.type)));
      expect(prose.menuItems.length, lessThan(full.menuItems.length));
      expect(
        prose.markdownDecoders.length,
        lessThan(full.markdownDecoders.length),
      );
    });

    test('what is left keeps working on its own', () {
      final prose = defaultRichTextFeatures.without<CodeBlockFeature>();

      expect(prose.features.whereType<LinkFeature>(), isNotEmpty);
      expect(prose.toolbarItems, isNotEmpty);
      // The paragraph feature is still there, so blank lines still survive.
      final codec = MarkdownRichTextCodec(features: prose);
      final blocks = codec
          .decode(
            codec.encode(
              Document.blank()..insert([0], [paragraphNode(), paragraphNode()]),
            ),
          )
          .root
          .children;

      expect(blocks, hasLength(2));
    });

    test('and puts one back', () {
      final restored = defaultRichTextFeatures.without<CodeBlockFeature>().and([
        const CodeBlockFeature(),
      ]);

      expect(restored.builders, contains(CodeBlockKeys.type));
    });
  });

  group('the affordances that are not features', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pump();
    }

    testWidgets('the left gutter is off unless a page asks for it', (
      tester,
    ) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Sans gouttière'),
        ),
      );

      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('Sans gouttière', findRichText: true), findsOneWidget);
    });

    testWidgets('the toolbar can be left out', (tester) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Nu'),
          toolbar: false,
        ),
      );

      expect(find.byType(FloatingToolbar), findsNothing);
      expect(find.text('Nu', findRichText: true), findsOneWidget);
    });

    testWidgets('the toolbar offers what it is given, features appended', (
      tester,
    ) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Marques seules'),
          toolbarItems: RichTextToolbar.marks,
        ),
      );

      final toolbar = tester.widget<FloatingToolbar>(
        find.byType(FloatingToolbar),
      );
      final ids = toolbar.items.map((item) => item.id);

      expect(ids, containsAll(RichTextToolbar.marks.map((item) => item.id)));
      // Narrowing the items drops the headings but never the features': a link
      // stays reachable unless the feature itself is dropped.
      expect(ids, isNot(contains('editor.h1')));
      expect(ids, contains(LinkFeature.id));
    });

    testWidgets('the standard set is what it offers by default', (
      tester,
    ) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Tout'),
        ),
      );

      final toolbar = tester.widget<FloatingToolbar>(
        find.byType(FloatingToolbar),
      );

      expect(
        toolbar.items,
        hasLength(
          RichTextToolbar.standard.length +
              defaultRichTextFeatures.toolbarItems.length,
        ),
      );
    });

    testWidgets('the "/" menu can be left out', (tester) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Nu'),
          slashMenu: false,
        ),
      );

      expect(find.byType(AppFlowyEditor), findsOneWidget);
      final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));

      expect(
        editor.characterShortcutEvents.any((event) => event.character == '/'),
        isFalse,
      );
    });

    testWidgets('and is there by default', (tester) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Nu'),
        ),
      );

      final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));

      expect(
        editor.characterShortcutEvents.any((event) => event.character == '/'),
        isTrue,
      );
    });
  });
}
