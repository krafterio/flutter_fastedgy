/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Document documentOf(List<Node> nodes) => Document.blank()..insert([0], nodes);

  Document codeBlockDocument({
    String code = 'print("hi")',
    String? language = 'python',
  }) => documentOf([
    codeBlockNode(delta: Delta()..insert(code), language: language),
  ]);

  group('markdown', () {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

    test('a code block survives the round trip, language included', () {
      final markdown = codec.encode(
        documentOf([
          paragraphNode(delta: Delta()..insert('Avant')),
          codeBlockNode(
            delta: Delta()..insert('print("hi")'),
            language: 'python',
          ),
          paragraphNode(delta: Delta()..insert('Après')),
        ]),
      );

      final blocks = codec.decode(markdown).root.children;

      expect(blocks.map((block) => block.type), [
        'paragraph',
        CodeBlockKeys.type,
        'paragraph',
      ]);
      expect(blocks[1].attributes[CodeBlockKeys.language], 'python');
      expect(blocks[1].delta?.toPlainText(), 'print("hi")');
    });

    test('a code block with no language survives too', () {
      final blocks = codec
          .decode(
            codec.encode(codeBlockDocument(code: 'plain', language: null)),
          )
          .root
          .children;

      expect(blocks.map((block) => block.type), [CodeBlockKeys.type]);
      expect(blocks.first.delta?.toPlainText(), 'plain');
    });

    test(
      'a multi-line code block keeps its line breaks and no trailing one',
      () {
        const code = 'def hi():\n    return 1';

        final blocks = codec
            .decode(codec.encode(codeBlockDocument(code: code)))
            .root
            .children;

        expect(blocks.first.delta?.toPlainText(), code);
      },
    );

    test('the blank lines a writer typed are kept, however many', () {
      final blocks = codec
          .decode(
            codec.encode(
              documentOf([
                paragraphNode(delta: Delta()..insert('Saut 1')),
                paragraphNode(),
                paragraphNode(delta: Delta()..insert('Saut 2')),
                paragraphNode(),
                paragraphNode(),
                paragraphNode(delta: Delta()..insert('Super')),
              ]),
            ),
          )
          .root
          .children;

      expect(blocks.map((block) => block.delta?.toPlainText()), [
        'Saut 1',
        '',
        'Saut 2',
        '',
        '',
        'Super',
      ]);
    });

    test('two paragraphs typed one after the other stay two', () {
      final blocks = codec
          .decode(
            codec.encode(
              documentOf([
                paragraphNode(delta: Delta()..insert('A')),
                paragraphNode(delta: Delta()..insert('B')),
              ]),
            ),
          )
          .root
          .children;

      expect(blocks.map((block) => block.delta?.toPlainText()), ['A', 'B']);
    });

    test('a blank line under a quote or a list is not swallowed by it', () {
      final blocks = codec
          .decode(
            codec.encode(
              documentOf([
                quoteNode(delta: Delta()..insert('test')),
                paragraphNode(),
                paragraphNode(delta: Delta()..insert('Saut')),
                numberedListNode(delta: Delta()..insert('Item 1')),
                numberedListNode(delta: Delta()..insert('Item 2')),
                paragraphNode(),
                paragraphNode(delta: Delta()..insert('Super')),
              ]),
            ),
          )
          .root
          .children;

      expect(blocks.map((block) => block.type), [
        QuoteBlockKeys.type,
        ParagraphBlockKeys.type,
        ParagraphBlockKeys.type,
        NumberedListBlockKeys.type,
        NumberedListBlockKeys.type,
        ParagraphBlockKeys.type,
        ParagraphBlockKeys.type,
      ]);
      expect(blocks.map((block) => block.delta?.toPlainText()), [
        'test',
        '',
        'Saut',
        'Item 1',
        'Item 2',
        '',
        'Super',
      ]);
    });

    test('a todo list keeps its items tight, blank line free', () {
      final blocks = codec
          .decode(
            codec.encode(
              documentOf([
                todoListNode(checked: true, delta: Delta()..insert('Fait')),
                todoListNode(checked: false, delta: Delta()..insert('À faire')),
              ]),
            ),
          )
          .root
          .children;

      expect(blocks.map((block) => block.type), [
        TodoListBlockKeys.type,
        TodoListBlockKeys.type,
      ]);
      expect(blocks.map((block) => block.delta?.toPlainText()), [
        'Fait',
        'À faire',
      ]);
    });

    test('a nested list keeps its child', () {
      final blocks = codec
          .decode(
            codec.encode(
              documentOf([
                bulletedListNode(
                  delta: Delta()..insert('Parent'),
                  children: [
                    bulletedListNode(delta: Delta()..insert('Enfant')),
                  ],
                ),
              ]),
            ),
          )
          .root
          .children;

      expect(blocks.single.children.single.delta?.toPlainText(), 'Enfant');
    });

    group('links', () {
      Node linked(String text, String href, {bool bold = false}) =>
          paragraphNode(
            delta: Delta()
              ..insert(
                text,
                attributes: {'href': href, if (bold) 'bold': true},
              ),
          );

      Node roundTrip(Node node) =>
          codec.decode(codec.encode(documentOf([node]))).root.children.first;

      test('a labelled link keeps its label', () {
        final markdown = codec.encode(
          documentOf([linked('Example', 'https://example.org')]),
        );

        expect(markdown, '[Example](https://example.org)');
        expect(
          roundTrip(linked('Example', 'https://example.org')).delta
              ?.toPlainText(),
          'Example',
        );
      });

      test(
        'a link to its own text is written bare, and read back as a link',
        () {
          final markdown = codec.encode(
            documentOf([linked('https://example.org', 'https://example.org')]),
          );

          // `[url](url)` says nothing the bare URL does not: markdown autolinks it.
          expect(markdown, 'https://example.org');
          expect(
            roundTrip(linked('https://example.org', 'https://example.org'))
                .delta
                ?.first
                .attributes,
            containsPair('href', 'https://example.org'),
          );
        },
      );

      test('a URL typed as plain text comes back a link', () {
        final blocks = codec.decode('https://example.org').root.children;

        expect(
          blocks.single.delta?.first.attributes,
          containsPair('href', 'https://example.org'),
        );
      });

      test('dropping the redundant href leaves the other formatting alone', () {
        final markdown = codec.encode(
          documentOf([
            linked('https://example.org', 'https://example.org', bold: true),
          ]),
        );

        expect(markdown, '**https://example.org**');
        expect(
          roundTrip(
            linked('https://example.org', 'https://example.org', bold: true),
          ).delta?.first.attributes,
          allOf(
            containsPair('bold', true),
            containsPair('href', 'https://example.org'),
          ),
        );
      });
    });

    test('markdown holding nothing readable still opens on a paragraph to type into', () {
      expect(
        codec.decode('<!-- -->').root.children.map((block) => block.type),
        ['paragraph'],
      );
    });

    test('an absent or blank source opens on a paragraph', () {
      expect(codec.decode(null).root.children.map((block) => block.type), [
        'paragraph',
      ]);
      expect(codec.decode('   \n  ').root.children.map((block) => block.type), [
        'paragraph',
      ]);
    });

    test(
      'without its feature the package writes a code block it cannot read back',
      () {
        const bare = MarkdownRichTextCodec(features: RichTextFeatures([]));

        final markdown = bare.encode(codeBlockDocument());

        expect(markdown, contains('```python'));
        // Half a round trip is what the feature's decoder is there to close.
        expect(bare.decode(markdown).root.children.map((block) => block.type), [
          'paragraph',
        ]);
      },
    );
  });

  group('json', () {
    const codec = JsonRichTextCodec();

    test(
      'a code block survives the round trip without any feature declaring it',
      () {
        final blocks = codec
            .decode(codec.encode(codeBlockDocument()))
            .root
            .children;

        expect(blocks.map((block) => block.type), [CodeBlockKeys.type]);
        expect(blocks.first.attributes[CodeBlockKeys.language], 'python');
        expect(blocks.first.delta?.toPlainText(), 'print("hi")');
      },
    );

    test('an absent, blank or unreadable source opens on a paragraph', () {
      expect(codec.decode(null).root.children.map((block) => block.type), [
        'paragraph',
      ]);
      expect(codec.decode('  ').root.children.map((block) => block.type), [
        'paragraph',
      ]);
      expect(
        codec
            .decode('not json at all')
            .root
            .children
            .map((block) => block.type),
        ['paragraph'],
      );
    });
  });

  group('emptiness', () {
    const markdown = MarkdownRichTextCodec(features: defaultRichTextFeatures);
    const json = JsonRichTextCodec();

    test('a document that says nothing encodes to nothing', () {
      for (final document in [
        RichTextCodec.blank,
        Document.blank(),
        documentOf([paragraphNode(delta: Delta()..insert('   '))]),
        documentOf([headingNode(level: 1)]),
      ]) {
        expect(markdown.encode(document), '');
        expect(json.encode(document), '');
      }
    });

    test('what a cleared field stores comes back cleared', () {
      expect(
        markdown.encode(markdown.decode(markdown.encode(RichTextCodec.blank))),
        '',
      );
      expect(json.encode(json.decode(json.encode(RichTextCodec.blank))), '');
    });

    test('a field holding nothing but the marker comes back cleared', () {
      for (final stored in ['&nbsp;', '&nbsp;\n', '\n&nbsp;\n\n']) {
        expect(markdown.encode(markdown.decode(stored)), '', reason: stored);
      }
    });

    test('blank lines somebody left standing are still theirs to keep', () {
      final document = documentOf([paragraphNode(), paragraphNode()]);

      expect(markdown.encode(document), isNot(''));
      expect(
        markdown.decode(markdown.encode(document)).root.children,
        hasLength(2),
      );
    });

    test('a document holding a single word still encodes it', () {
      final document = documentOf([
        paragraphNode(delta: Delta()..insert('Lait')),
      ]);

      expect(markdown.encode(document), 'Lait');
      expect(json.encode(document), isNot(''));
    });
  });

  group('les blancs autour de ce qui est marqué', () {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

    List<TextInsert> runsOf(String markdown) => codec
        .decode(markdown)
        .root
        .children
        .first
        .delta!
        .toList()
        .cast<TextInsert>();

    Document paragraphOf(Delta delta) =>
        Document.blank()..insert([0], [paragraphNode(delta: delta)]);

    test('un blanc pris dans la sélection sort des marqueurs', () {
      final markdown = codec.encode(
        paragraphOf(
          Delta()
            ..insert('Coucou')
            ..insert(' toi !', attributes: {'bold': true, 'italic': true}),
        ),
      );

      // `**` ouvre sur ce qui suit : contre un blanc il n'ouvre rien, et le
      // texte revenait avec ses étoiles et aucun gras.
      expect(markdown, 'Coucou ***toi !***');

      final runs = runsOf(markdown);

      expect(runs.map((run) => run.text), ['Coucou ', 'toi !']);
      expect(runs.last.attributes?['bold'], isTrue);
      expect(runs.last.attributes?['italic'], isTrue);
    });

    test('rien à déplacer laisse le passage tel quel', () {
      final markdown = codec.encode(
        paragraphOf(
          Delta()
            ..insert('Un ')
            ..insert('mot', attributes: {'bold': true})
            ..insert(' gras'),
        ),
      );

      expect(markdown, 'Un **mot** gras');
    });

    test('un passage qui n\'est que du blanc perd ses marqueurs', () {
      final markdown = codec.encode(
        paragraphOf(
          Delta()
            ..insert('Avant')
            ..insert(' ', attributes: {'bold': true})
            ..insert('après'),
        ),
      );

      expect(markdown, 'Avant après');
    });
  });

  group('ce qui ouvrirait un bloc en tête de ligne', () {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

    Document documentOf(List<Node> nodes) =>
        Document.blank()..insert([0], nodes);

    Node reread(Document document) =>
        codec.decode(codec.encode(document)).root.children.first;

    /// Le texte est écrit dans un paragraphe, et doit revenir un paragraphe
    /// portant exactement les mêmes caractères.
    void survives(String text) {
      final block = reread(
        documentOf([paragraphNode(delta: Delta()..insert(text))]),
      );

      expect(block.type, ParagraphBlockKeys.type, reason: text);
      expect(block.delta?.toPlainText(), text, reason: text);
    }

    test('un dièse reste un dièse et pas un titre', () {
      final markdown = codec.encode(
        documentOf([paragraphNode(delta: Delta()..insert('# Test non titre'))]),
      );

      expect(markdown, r'\# Test non titre');

      survives('# Test non titre');
    });

    test('et tout ce que le lecteur sait ouvrir avec', () {
      survives('## Deux');
      survives('- pas une liste');
      survives('* pas une puce');
      survives('1. pas une liste');
      survives('> pas une citation');
      survives('```pas du code');
      survives('![](https://example.org/a.png)');
    });

    test('ce qui n\'ouvre rien n\'est pas échappé pour autant', () {
      final markdown = codec.encode(
        documentOf([
          paragraphNode(delta: Delta()..insert('(entre parenthèses)')),
          paragraphNode(delta: Delta()..insert('--- pas une règle')),
          paragraphNode(delta: Delta()..insert('C:\\chemin')),
        ]),
      );

      expect(
        markdown,
        '(entre parenthèses)\n\n--- pas une règle\n\nC:\\chemin',
      );
    });

    test('un marqueur dans un bloc qui en est déjà un', () {
      final quote = reread(
        documentOf([quoteNode(delta: Delta()..insert('# pas un titre'))]),
      );

      expect(quote.type, QuoteBlockKeys.type);
      expect(quote.delta?.toPlainText(), '# pas un titre');
    });

    test('le contenu d\'un bloc de code n\'est jamais échappé', () {
      final markdown = codec.encode(
        documentOf([
          codeBlockNode(
            delta: Delta()..insert('# commentaire'),
            language: 'python',
          ),
        ]),
      );

      expect(markdown, contains('# commentaire'));
      expect(markdown, isNot(contains(r'\#')));
    });

    test('les marques du passage survivent à l\'échappement', () {
      final markdown = codec.encode(
        documentOf([
          paragraphNode(
            delta: Delta()
              ..insert('# ')
              ..insert('gras', attributes: {'bold': true}),
          ),
        ]),
      );

      expect(markdown, r'\# **gras**');

      final block = codec.decode(markdown).root.children.first;
      final runs = block.delta!.toList().cast<TextInsert>();

      expect(block.delta?.toPlainText(), '# gras');
      expect(runs.last.attributes?['bold'], isTrue);
    });
  });
}
