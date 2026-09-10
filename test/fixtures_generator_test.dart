/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// Writes the shared markdown corpus. Run it, read what it produced, then copy
// the folder into every other implementation of the format. It is a generator
// rather than a test, and lives here because this is where the format is
// defined.
//
//   flutter test test/fixtures_generator_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus_support.dart';

void main() {
  final codec = corpusCodec;
  final directory = Directory(corpusDirectory);
  final lenient = Directory('$corpusDirectory/lenient');

  Document documentOf(List<Node> nodes) => Document.blank()..insert([0], nodes);

  Node nested(Node parent, List<Node> children) {
    for (final child in children) {
      parent.insert(child);
    }

    return parent;
  }

  void write(Directory into, String name, String markdown) {
    final outline = outlineOf(codec.decode(markdown));

    File('${into.path}/$name.md').writeAsStringSync(markdown);
    File('${into.path}/$name.outline.json')
        .writeAsStringSync('${const JsonEncoder.withIndent('    ').convert(outline)}\n');
  }

  /// A fixture the encoder produced: canonical, and held to all three assertions.
  void fromDocument(String name, Document document) {
    final markdown = codec.encode(document);

    // A corpus entry that does not survive its own round trip here would ask the
    // other side to reproduce a bug rather than a format.
    expect(codec.encode(codec.decode(markdown)), markdown, reason: name);
    write(directory, name, markdown);
  }

  /// A fixture written by hand: only ever read, never expected to come back as
  /// it went. Content stored by an older editor lives here.
  void fromMarkdown(String name, String markdown) => write(lenient, name, markdown);

  /// A fixture whose source is written by hand, held to the same three
  /// assertions as one the encoder produced. What a table is made of is far
  /// easier to say in markdown than in nodes, and the round trip is what the
  /// corpus asserts either way.
  void fromCanonicalMarkdown(String name, String markdown) {
    expect(codec.encode(codec.decode(markdown)), markdown, reason: name);
    write(directory, name, markdown);
  }

  test('writes the shared markdown corpus', () {
    useCorpusServices();
    directory.createSync(recursive: true);
    lenient.createSync(recursive: true);

    fromDocument(
      'blocks_all',
      documentOf([
        paragraphNode(delta: Delta()..insert('Un paragraphe.')),
        headingNode(level: 1, delta: Delta()..insert('Titre 1')),
        headingNode(level: 2, delta: Delta()..insert('Titre 2')),
        headingNode(level: 3, delta: Delta()..insert('Titre 3')),
        bulletedListNode(delta: Delta()..insert('une puce')),
        numberedListNode(delta: Delta()..insert('un'), number: 1),
        numberedListNode(delta: Delta()..insert('deux'), number: 2),
        todoListNode(checked: false, delta: Delta()..insert('à faire')),
        todoListNode(checked: true, delta: Delta()..insert('fait')),
        quoteNode(delta: Delta()..insert('une citation')),
        dividerNode(),
        codeBlockNode(delta: Delta()..insert('const a = 1;'), language: 'javascript'),
        codeBlockNode(delta: Delta()..insert('sans langue'), language: null),
      ]),
    );

    fromDocument(
      'marks_all',
      documentOf([
        paragraphNode(
          delta: Delta()
            ..insert('gras', attributes: {'bold': true})
            ..insert(' ')
            ..insert('italique', attributes: {'italic': true})
            ..insert(' ')
            ..insert('les deux', attributes: {'bold': true, 'italic': true})
            ..insert(' ')
            ..insert('barré', attributes: {'strikethrough': true})
            ..insert(' ')
            ..insert('souligné', attributes: {'underline': true})
            ..insert(' ')
            ..insert('code', attributes: {'code': true})
            ..insert(' ')
            ..insert('un lien', attributes: {AppFlowyRichTextKeys.href: 'https://melimelo.app'}),
        ),
      ]),
    );

    fromDocument(
      'marks_spaced',
      documentOf([
        paragraphNode(
          delta: Delta()
            ..insert('avant')
            ..insert(' mot ', attributes: {'bold': true})
            ..insert('après'),
        ),
      ]),
    );

    fromDocument(
      'link_to_itself',
      documentOf([
        paragraphNode(
          delta: Delta()
            ..insert('voir ')
            ..insert('https://melimelo.app', attributes: {AppFlowyRichTextKeys.href: 'https://melimelo.app'}),
        ),
      ]),
    );

    fromDocument(
      'ambiguous_openers',
      documentOf([
        for (final text in [
          '# pas un titre',
          '- pas une puce',
          '> pas une citation',
          '1. pas une liste',
          '---',
          '***',
          '```js',
          '#### quatre',
        ])
          paragraphNode(delta: Delta()..insert(text)),
      ]),
    );

    fromDocument(
      'blank_paragraph',
      documentOf([
        paragraphNode(delta: Delta()..insert('un')),
        paragraphNode(),
        paragraphNode(delta: Delta()..insert('deux')),
      ]),
    );

    fromDocument(
      'nesting_three_levels',
      documentOf([
        nested(bulletedListNode(delta: Delta()..insert('a')), [
          nested(bulletedListNode(delta: Delta()..insert('a.1')), [
            paragraphNode(delta: Delta()..insert('un paragraphe sous a.1')),
          ]),
          bulletedListNode(delta: Delta()..insert('a.2')),
        ]),
        bulletedListNode(delta: Delta()..insert('b')),
      ]),
    );

    fromDocument(
      'code_blank_line',
      documentOf([
        codeBlockNode(delta: Delta()..insert('const a = 1;\n\nconst b = 2;'), language: 'javascript'),
        paragraphNode(delta: Delta()..insert('après')),
      ]),
    );

    fromDocument(
      'image_attachment',
      documentOf([imageNode(url: 'attachment:15', width: 420, height: 280)]),
    );

    fromDocument(
      'image_in_document',
      documentOf([
        paragraphNode(delta: Delta()..insert('avant')),
        imageNode(url: 'data:image/png;base64,iVBORw0KGgo='),
        paragraphNode(delta: Delta()..insert('après')),
      ]),
    );

    fromCanonicalMarkdown('mention_note', 'voir [Courses de la semaine](/notes/12) ce soir');
    fromCanonicalMarkdown('mention_member', 'avec [François](/household/members/7)');
    fromCanonicalMarkdown('mention_email_label', 'avec [jean\\@melimelo.app](/household/members/9)');
    fromCanonicalMarkdown(
      'mention_in_cell',
      '|qui|quand|\n|-|-|\n|[François](/household/members/7)|demain|',
    );

    fromCanonicalMarkdown('table_plain', '|a|b|\n|-|-|\n|c|d|');
    fromCanonicalMarkdown('table_empty_cell', '|a||\n|-|-|\n||d|');
    fromCanonicalMarkdown('table_cell_pipe', '|a\\|b|c|\n|-|-|\n|d|e|');
    fromCanonicalMarkdown('table_cell_break', '|ligne 1<br>ligne 2|b|\n|-|-|\n|c|d|');
    fromCanonicalMarkdown('table_widths', '|a|b|\n|-|-|\n|c|d|\n<!-- cols:180,240 -->');

    // Found on real notes, and none of them was in the corpus: an item with
    // nothing in it, a line cut inside a block, and a bare URL whose letters
    // were spelt one way or the other.
    fromCanonicalMarkdown('list_empty_items', '*\n\n*\n\n* Tapis');
    fromCanonicalMarkdown('line_breaks', 'un\ndeux\ntrois');
    fromCanonicalMarkdown('link_bare_encoded', 'https://a.fr/jeans-%C3%A9cussons');
    fromCanonicalMarkdown('link_bare_letters', 'https://a.fr/décoration');

    // A fence holding a fence: read back as far as the format can, and not
    // expected to come back as it went. The inner ``` closes the block for any
    // reader, this one included, and what follows lands beside it.
    fromMarkdown('code_fence_inside', '```markdown\n```\nune fence dans la fence\n```\n```\n\naprès');

    fromMarkdown('nesting_tabs', 'a\n\n\tb\n\n\t\tc\n\nd');
    fromMarkdown('plus_underline', '++venu de Fleather++ et C++ and C++');
    fromMarkdown('compact_list', '* a\n* b\n* c');

    final written = directory.listSync().whereType<File>().length + lenient.listSync().whereType<File>().length;

    expect(written, greaterThan(0));
    // ignore: avoid_print
    print('corpus: $written fichiers dans ${directory.path}');
  });
}
