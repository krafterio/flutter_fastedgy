/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderParagraph;
import 'package:material_ui/material_ui.dart';
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

  double? fontSizeOf(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(text, findRichText: true),
    );
    double? size;

    paragraph.text.visitChildren((span) {
      size ??= span.style?.fontSize;

      return size == null;
    });

    return size;
  }

  testWidgets(
    'draws a heading at the size the theme names, not the package\'s',
    (tester) async {
      await pump(
        tester,
        FastEdgyTheme(
          data: FastEdgyThemeData.fallback.copyWith(
            typography: TypographyRoles.fallback.copyWith(
              heading: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child: RichTextViewer(
            features: defaultRichTextFeatures,
            editorState: stateOf([
              headingNode(level: 1, delta: Delta()..insert('Titre')),
              headingNode(level: 3, delta: Delta()..insert('Section')),
            ]),
          ),
        ),
      );

      // The package's own would be 28 and 18, from a list written into its
      // source.
      expect(
        fontSizeOf(tester, 'Titre'),
        30 * RichTextTheme.defaultHeadingScale.first,
      );
      expect(
        fontSizeOf(tester, 'Section'),
        30 * RichTextTheme.defaultHeadingScale[2],
      );
    },
  );

  double topOf(WidgetTester tester, String text) => tester
      .renderObject<RenderBox>(find.text(text, findRichText: true))
      .localToGlobal(Offset.zero)
      .dy;

  Future<double> headingTop(
    WidgetTester tester, {
    required List<Node> nodes,
    required bool spaced,
  }) async {
    final state = EditorState(document: Document.blank()..insert([0], nodes));
    addTearDown(state.dispose);

    await pump(
      tester,
      FastEdgyTheme(
        data: FastEdgyThemeData.fallback.copyWith(
          components: {
            if (!spaced)
              RichTextTheme: RichTextTheme.fallback.copyWith(
                headingMargin: List.filled(6, EdgeInsets.zero),
              ),
          },
        ),
        child: RichTextViewer(
          editorState: state,
          features: defaultRichTextFeatures,
        ),
      ),
    );

    return topOf(tester, 'Titre');
  }

  testWidgets('a heading holds the air the theme names above it', (
    tester,
  ) async {
    final nodes = [
      paragraphNode(delta: Delta()..insert('Texte')),
      headingNode(level: 1, delta: Delta()..insert('Titre')),
    ];

    final flush = await headingTop(tester, nodes: nodes, spaced: false);
    final spaced = await headingTop(tester, nodes: nodes, spaced: true);

    expect(spaced - flush, RichTextTheme.fallback.headingMarginAt(1).top);
  });

  testWidgets('but none above the one that opens the page', (tester) async {
    final nodes = [headingNode(level: 1, delta: Delta()..insert('Titre'))];

    final flush = await headingTop(tester, nodes: nodes, spaced: false);
    final spaced = await headingTop(tester, nodes: nodes, spaced: true);

    expect(spaced, flush);
  });

  testWidgets('renders down a list, where the height is unbounded', (
    tester,
  ) async {
    await pump(
      tester,
      ListView(
        children: [
          RichTextViewer(
            editorState: textOf('Premier message'),
            features: defaultRichTextFeatures,
          ),
          RichTextViewer(
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
      RichTextViewer(
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
      RichTextViewer(
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
        child: RichTextViewer(
          editorState: textOf('Une ligne'),
          features: defaultRichTextFeatures,
        ),
      ),
    );

    expect(tester.getSize(find.byType(RichTextViewer)).height, lessThan(120));
  });
}
