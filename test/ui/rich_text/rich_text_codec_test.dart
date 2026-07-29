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
          roundTrip(
            linked('Example', 'https://example.org'),
          ).delta?.toPlainText(),
          'Example',
        );
      });

      test('a link to its own text is written bare, and read back as a link', () {
        final markdown = codec.encode(
          documentOf([linked('https://example.org', 'https://example.org')]),
        );

        // `[url](url)` says nothing the bare URL does not: markdown autolinks it.
        expect(markdown, 'https://example.org');
        expect(
          roundTrip(
            linked('https://example.org', 'https://example.org'),
          ).delta?.first.attributes,
          containsPair('href', 'https://example.org'),
        );
      });

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

    test(
      'markdown holding nothing readable still opens on a paragraph to type into',
      () {
        expect(
          codec.decode('<!-- -->').root.children.map((block) => block.type),
          ['paragraph'],
        );
      },
    );

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
}
