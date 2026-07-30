/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

/// A one-pixel PNG, as a fetched picture would come back.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  group('what reads as markdown', () {
    test('a marked span says so on its own, on a single line', () {
      expect(looksLikeMarkdown('see **this**'), isTrue);
      expect(looksLikeMarkdown('a [link](https://example.org)'), isTrue);
      expect(looksLikeMarkdown('![](https://example.org/a.png)'), isTrue);
      expect(looksLikeMarkdown('run `flutter test`'), isTrue);
    });

    test('a block marker counts only where there are lines to structure', () {
      expect(looksLikeMarkdown('# Title\n\nSomething'), isTrue);
      expect(looksLikeMarkdown('- one\n- two'), isTrue);
      expect(looksLikeMarkdown('1. one\n2. two'), isTrue);
      expect(looksLikeMarkdown('| a | b |\n| - | - |'), isTrue);

      // On its own a line opening with a marker is far more often a tag, a
      // shell prompt or a bullet somebody typed than a document.
      expect(looksLikeMarkdown('# groceries'), isFalse);
      expect(looksLikeMarkdown('- milk'), isFalse);
    });

    test('ordinary writing is not markdown', () {
      expect(looksLikeMarkdown('Bonjour, comment ça va ?'), isFalse);
      expect(looksLikeMarkdown('5 * 3 * 2 = 30'), isFalse);
      expect(looksLikeMarkdown('Deux lignes\nsans rien de spécial'), isFalse);
      expect(looksLikeMarkdown('   '), isFalse);
    });
  });

  group('pasting markdown', () {
    EditorState blank() {
      final state = EditorState(document: Document.blank(withInitialText: true))
        ..selection = Selection.collapsed(Position(path: [0], offset: 0));
      addTearDown(state.dispose);

      return state;
    }

    List<String> blocksOf(EditorState state) => [
      for (final node in state.document.root.children) node.type,
    ];

    test('a document arrives as the blocks it describes', () async {
      final state = blank();

      final pasted = await pasteMarkdown(
        state,
        '# Titre\n\n- un\n- deux',
        features: defaultRichTextFeatures,
      );

      expect(pasted, isTrue);
      expect(blocksOf(state), [
        HeadingBlockKeys.type,
        BulletedListBlockKeys.type,
        BulletedListBlockKeys.type,
      ]);
      expect(state.getNodeAtPath([0])?.delta?.toPlainText(), 'Titre');
    });

    test('what is not markdown is left to the plain paste', () async {
      final state = blank();

      final pasted = await pasteMarkdown(
        state,
        'Juste une phrase',
        features: defaultRichTextFeatures,
      );

      expect(pasted, isFalse);
      expect(state.getNodeAtPath([0])?.delta?.toPlainText(), isEmpty);
    });

    test('a remote picture is brought into the document', () async {
      final state = blank();
      final asked = <String>[];

      await pasteMarkdown(
        state,
        'Voici la photo :\n\n![](https://example.org/a.png)',
        features: defaultRichTextFeatures,
        fetchImage: (url) async {
          asked.add(url);

          return _png;
        },
      );

      final image = state.document.root.children.last;

      expect(asked, ['https://example.org/a.png']);
      expect(image.type, ImageBlockKeys.type);
      // Inline, which is what a save turns into an attachment of the record.
      expect(
        inlineImageBytes(image.attributes[ImageBlockKeys.url] as String?),
        _png,
      );
    });

    test('one that cannot be had keeps pointing where it pointed', () async {
      final state = blank();

      await pasteMarkdown(
        state,
        'Voici la photo :\n\n![](https://example.org/gone.png)',
        features: defaultRichTextFeatures,
        fetchImage: (_) async => null,
      );

      expect(
        state.document.root.children.last.attributes[ImageBlockKeys.url],
        'https://example.org/gone.png',
      );
    });

    test('an attachment already stored is never fetched', () async {
      final state = blank();
      var asked = false;

      await pasteMarkdown(
        state,
        'Photo :\n\n![](attachment:42)',
        features: defaultRichTextFeatures,
        fetchImage: (_) async {
          asked = true;

          return _png;
        },
      );

      expect(asked, isFalse);
      expect(
        state.document.root.children.last.attributes[ImageBlockKeys.url],
        'attachment:42',
      );
    });

    test('a picture on its own takes the place of the blank line', () async {
      final state = blank();

      await pasteMarkdown(
        state,
        '![](https://example.org/a.png)',
        features: defaultRichTextFeatures,
        fetchImage: (_) async => _png,
      );

      expect(blocksOf(state), [ImageBlockKeys.type]);
    });
  });

  group('la barre qu\'un appui long lève', () {
    tearDown(() => AppFlowyClipboard.mockSetData(null));

    /// L'override doit être défait avant la fin du corps — le framework
    /// vérifie les drapeaux de debug de la fondation là.
    Future<void> onTouch(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    /// Flottante, la barre n'existe que sur une sélection : c'est là que
    /// l'appui long a quelque chose à lever. Ancrée, elle tient déjà sur le
    /// curseur et n'a besoin de personne.
    Future<EditorState> pump(WidgetTester tester, {required bool docked}) async {
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(delta: Delta()..insert('Bonjour'))]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ComponentTheme<RichTextToolbarTheme>(
                data: RichTextToolbarTheme.from(
                  RichTextTheme.of(context),
                  docked: docked,
                ),
                child: RichTextEditor(
                  features: defaultRichTextFeatures,
                  editorState: state,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      return state;
    }

    /// Un point sur le premier bloc : l'éditeur dessine son texte avec des
    /// spans à lui, qu'aucun finder de texte n'atteint.
    Offset onTheText(WidgetTester tester) =>
        tester.getTopLeft(find.byType(RichTextEditor)) + const Offset(40, 20);

    Finder pasteButton() =>
        find.byIcon(FastEdgyIcons.material[FastEdgyGlyph.paste]);

    testWidgets('offre au doigt ce que l\'éditeur ne lui offrait pas', (
      tester,
    ) async {
      await onTouch(() async {
        final state = await pump(tester, docked: false);

        expect(pasteButton(), findsNothing);

        state.selection = Selection.collapsed(Position(path: [0], offset: 3));
        await tester.longPressAt(onTheText(tester));
        await tester.pumpAndSettle();

        expect(pasteButton(), findsOneWidget);
      });
    });

    testWidgets('et colle le markdown qu\'on y prend', (tester) async {
      await onTouch(() async {
        final state = await pump(tester, docked: false);

        AppFlowyClipboard.mockSetData(
          const AppFlowyClipboardData(text: '# Titre\n\n- un\n- deux'),
        );

        state.selection = Selection.collapsed(Position(path: [0], offset: 3));
        await tester.longPressAt(onTheText(tester));
        await tester.pumpAndSettle();

        // La barre défile : le presse-papier est en bout de rangée, derrière
        // tout ce que l'écriture demande d'abord.
        await tester.ensureVisible(pasteButton());
        await tester.pumpAndSettle();

        await tester.tap(pasteButton());
        await tester.pumpAndSettle();

        expect([
          for (final node in state.document.root.children) node.type,
        ], contains(HeadingBlockKeys.type));
        expect(pasteButton(), findsNothing);
      });
    });

    testWidgets('une barre ancrée la porte déjà, rien n\'est levé', (
      tester,
    ) async {
      await onTouch(() async {
        final state = await pump(tester, docked: true);

        state.selection = Selection.collapsed(Position(path: [0], offset: 3));
        await tester.pumpAndSettle();

        // Elle est là, mais parce que la barre ancrée tient sur le curseur —
        // pas parce qu'un appui long l'a levée.
        expect(pasteButton(), findsOneWidget);

        await tester.longPressAt(onTheText(tester));
        await tester.pumpAndSettle();

        expect(pasteButton(), findsOneWidget);
      });
    });

    testWidgets('un simple tap ne la lève pas', (tester) async {
      await onTouch(() async {
        await pump(tester, docked: false);

        await tester.tapAt(onTheText(tester));
        await tester.pumpAndSettle();

        expect(pasteButton(), findsNothing);
      });
    });
  });

  group('the paste command', () {
    tearDown(() => AppFlowyClipboard.mockSetData(null));

    testWidgets('reads the clipboard and writes the blocks', (tester) async {
      final state = EditorState(document: Document.blank(withInitialText: true))
        ..selection = Selection.collapsed(Position(path: [0], offset: 0));
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
            ),
          ),
        ),
      );
      await tester.pump();

      AppFlowyClipboard.mockSetData(
        const AppFlowyClipboardData(text: '## Titre\n\n> Cité'),
      );

      final command = richTextPasteCommand(features: defaultRichTextFeatures);

      expect(command.handler(state), KeyEventResult.handled);
      await tester.pumpAndSettle();

      expect(
        [for (final node in state.document.root.children) node.type],
        [HeadingBlockKeys.type, QuoteBlockKeys.type],
      );
    });

    testWidgets('plain text still lands as plain text', (tester) async {
      final state = EditorState(document: Document.blank(withInitialText: true))
        ..selection = Selection.collapsed(Position(path: [0], offset: 0));
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
            ),
          ),
        ),
      );
      await tester.pump();

      AppFlowyClipboard.mockSetData(
        const AppFlowyClipboardData(text: 'Une phrase collée'),
      );

      richTextPasteCommand(features: defaultRichTextFeatures).handler(state);
      await tester.pumpAndSettle();

      expect(
        state.getNodeAtPath([0])?.delta?.toPlainText(),
        'Une phrase collée',
      );
    });
  });
}
