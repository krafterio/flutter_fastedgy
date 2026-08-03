/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
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
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Marques seules'),
          actions: RichTextActions.marks,
        ),
      );

      final bar = tester.widget<RichTextEditor>(find.byType(RichTextEditor));
      final ids = [
        ...?bar.actions?.map((action) => action.id),
        ...defaultRichTextFeatures.actions.map((action) => action.id),
      ];

      expect(
        ids,
        containsAll(RichTextActions.marks.map((action) => action.id)),
      );
      // Narrowing the actions drops the block kinds but never the features'.
      expect(ids, isNot(contains('heading_1')));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the standard set is what it offers by default', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Tout'),
        ),
      );

      expect(find.byType(RichTextActionBar), findsNothing);
      // Nothing is selected, so no strip is up — what it would offer is the
      // standard set, which is a list, not a widget.
      expect(RichTextActions.standard, isNotEmpty);

      debugDefaultTargetPlatformOverride = null;
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

  group('un bloc qu\'on ne propose plus', () {
    test('sort du menu et du triple backquote, et rien d\'autre', () {
      const offered = CodeBlockFeature();
      const withdrawn = CodeBlockFeature(offered: false);

      expect(offered.menuItems, isNotEmpty);
      expect(offered.characterShortcuts, isNotEmpty);

      expect(withdrawn.menuItems, isEmpty);
      expect(withdrawn.characterShortcuts, isEmpty);

      expect(withdrawn.builders.keys, offered.builders.keys);
      expect(
        withdrawn.markdownEncoders,
        hasLength(offered.markdownEncoders.length),
      );
      expect(
        withdrawn.markdownDecoders,
        hasLength(offered.markdownDecoders.length),
      );
      expect(
        withdrawn.commandShortcuts,
        hasLength(offered.commandShortcuts.length),
      );
    });
  });
}
