/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

  Node text(String value, {List<Node> children = const []}) =>
      paragraphNode(delta: Delta()..insert(value), children: children);

  Node bullet(String value, {List<Node> children = const []}) =>
      bulletedListNode(delta: Delta()..insert(value), children: children);

  Document documentOf(List<Node> nodes) => Document.blank()..insert([0], nodes);

  /// The tree as `type "text"` lines, one per block, indented by depth.
  List<String> shapeOf(Document document) {
    final lines = <String>[];

    void walk(Node node, int depth) {
      lines.add(
        '${'  ' * depth}${node.type} "${node.delta?.toPlainText() ?? ''}"',
      );

      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final node in document.root.children) {
      walk(node, 0);
    }

    return lines;
  }

  List<String> roundTrip(List<Node> nodes) =>
      shapeOf(codec.decode(codec.encode(documentOf(nodes))));

  group('a block written under another', () {
    test('a paragraph under a paragraph comes back as a child', () {
      // Markdown nests nothing but list items, and the package glued the child
      // into its parent's own text, newline and tab included — which the next
      // save then read as a code block. Indentation is ours to mean nesting:
      // a code block of ours is always fenced, so nothing else claims it.
      expect(
        roundTrip([
          text('Parent', children: [text('Enfant')]),
        ]),
        ['paragraph "Parent"', '  paragraph "Enfant"'],
      );
    });

    test('a paragraph under a list item comes back as a child', () {
      expect(
        roundTrip([
          bullet('Un', children: [text('Detail')]),
        ]),
        ['bulleted_list "Un"', '  paragraph "Detail"'],
      );
    });

    test('a list under a list still comes back as one', () {
      expect(
        roundTrip([
          bullet('Un', children: [bullet('Deux')]),
        ]),
        ['bulleted_list "Un"', '  bulleted_list "Deux"'],
      );
    });

    test('three levels come back as three', () {
      expect(
        roundTrip([
          text(
            'A',
            children: [
              text('B', children: [text('C')]),
            ],
          ),
        ]),
        ['paragraph "A"', '  paragraph "B"', '    paragraph "C"'],
      );
    });

    test('what follows a child is a sibling of its parent again', () {
      expect(
        roundTrip([
          text('Parent', children: [text('Enfant')]),
          text('Suivant'),
        ]),
        ['paragraph "Parent"', '  paragraph "Enfant"', 'paragraph "Suivant"'],
      );
    });

    test('a heading keeps what hangs off it', () {
      expect(
        roundTrip([
          headingNode(
            level: 2,
            delta: Delta()..insert('Titre'),
          ).copyWith(children: [text('Sous')]),
        ]),
        ['heading "Titre"', '  paragraph "Sous"'],
      );
    });
  });

  group('a code block', () {
    test('at the top level still comes back whole', () {
      expect(
        roundTrip([
          codeBlockNode(
            delta: Delta()..insert('final x = 1;\nprint(x);'),
            language: 'dart',
          ),
        ]),
        ['code "final x = 1;\nprint(x);"'],
      );
    });

    test('nested under a block comes back nested and whole', () {
      expect(
        roundTrip([
          text(
            'Parent',
            children: [
              codeBlockNode(delta: Delta()..insert('x'), language: 'dart'),
            ],
          ),
        ]),
        ['paragraph "Parent"', '  code "x"'],
      );
    });

    test('is not cut in two by a blank line inside it', () {
      // A blank line ends a block everywhere else; inside a fence it is part of
      // the sample.
      expect(
        roundTrip([
          codeBlockNode(delta: Delta()..insert('one\n\ntwo'), language: 'dart'),
        ]),
        ['code "one\n\ntwo"'],
      );
    });
  });

  group('a table', () {
    /// Columns of rows, the way the package builds one.
    Node tableOf(List<List<String>> columns) => TableNode.fromList([
      for (final column in columns) [for (final cell in column) text(cell)],
    ]).node;

    test('is written whole, cells and all', () {
      // The cells are the table, not blocks nested under it. Handed the table
      // stripped of them the package's encoder threw on the first cell it went
      // looking for, and the autosave took the editor down with it.
      final markdown = codec.encode(
        documentOf([
          tableOf([
            ['a', 'c'],
            ['b', 'd'],
          ]),
        ]),
      );

      expect(markdown, '|a|b|\n|-|-|\n|c|d|');
    });

    test('comes back as a table, its cells where they were', () {
      expect(
        roundTrip([
          tableOf([
            ['a', 'c'],
            ['b', 'd'],
          ]),
        ]),
        [
          'table ""',
          '  table/cell ""',
          '    paragraph "a"',
          '  table/cell ""',
          '    paragraph "c"',
          '  table/cell ""',
          '    paragraph "b"',
          '  table/cell ""',
          '    paragraph "d"',
        ],
      );
    });

    test('stands between the blocks around it', () {
      expect(
        roundTrip([
          text('Avant'),
          tableOf([
            ['a', 'c'],
            ['b', 'd'],
          ]),
          text('Après'),
        ]).where((line) => !line.startsWith(' ')),
        ['paragraph "Avant"', 'table ""', 'paragraph "Après"'],
      );
    });
  });

  test('a document stored before this reads back as the tree it was', () {
    // What the package used to write: a tab, and no blank line. It came back as
    // one paragraph holding its child's text — the text was not lost, it was
    // welded on. Read as a level, it is a tree again.
    expect(shapeOf(codec.decode('Parent\n\tEnfant')), [
      'paragraph "Parent"',
      '  paragraph "Enfant"',
    ]);
  });

  test('a block indented under nothing stands on its own', () {
    expect(shapeOf(codec.decode('    Orphelin')), ['paragraph "Orphelin"']);
  });
}
