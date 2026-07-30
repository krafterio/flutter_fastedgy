/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const features = RichTextFeatures([
    ParagraphFeature(),
    PlusUnderlineFeature(),
  ]);
  const codec = MarkdownRichTextCodec(features: features);

  List<TextInsert> runsOf(RichTextCodec codec, String markdown) => codec
      .decode(markdown)
      .root
      .children
      .first
      .delta!
      .toList()
      .cast<TextInsert>();

  bool underlines(TextInsert run) =>
      run.attributes?[AppFlowyRichTextKeys.underline] == true;

  group('plus underline', () {
    test('++text++ reads as the underline it stands for', () {
      final runs = runsOf(codec, '++Lundi++');

      expect(runs.single.text, 'Lundi');
      expect(underlines(runs.single), isTrue);
    });

    test('what it reads is written back the one way the package writes', () {
      expect(codec.encode(codec.decode('++Lundi++')), '<u>Lundi</u>');
    });

    test('the marks around it are still read as marks', () {
      final runs = runsOf(codec, '**++Samedi midi :++**');

      expect(runs.single.text, 'Samedi midi :');
      expect(underlines(runs.single), isTrue);
      expect(runs.single.attributes?[AppFlowyRichTextKeys.bold], isTrue);
    });

    test('only what stands between the markers is underlined', () {
      final runs = runsOf(codec, 'Avant ++Lundi++ après');

      expect(runs.map((run) => run.text), ['Avant ', 'Lundi', ' après']);
      expect(runs.map(underlines), [false, true, false]);
    });

    test('markers glued to a word are the characters they look like', () {
      final runs = runsOf(codec, 'C++ et C++ sont un langage');

      expect(runs.single.text, 'C++ et C++ sont un langage');
      expect(underlines(runs.single), isFalse);
    });

    test('markers on either side of a line break underline nothing', () {
      final runs = runsOf(codec, '++Lundi\nMardi++');

      expect(runs.every(underlines), isFalse);
    });

    test('a code span keeps its markers as typed', () {
      final runs = runsOf(codec, 'Écrire `++Lundi++` souligne');

      expect(runs.map((run) => run.text), [
        'Écrire ',
        '++Lundi++',
        ' souligne',
      ]);
      expect(runs.every(underlines), isFalse);
    });

    test('a code block keeps its markers as typed', () {
      const withCode = MarkdownRichTextCodec(
        features: RichTextFeatures([
          ParagraphFeature(),
          CodeBlockFeature(),
          PlusUnderlineFeature(),
        ]),
      );

      final block = withCode.decode('```\nx ++1++\n```').root.children.single;

      expect(block.type, CodeBlockKeys.type);
      expect(block.delta?.toPlainText(), 'x ++1++');
    });

    test('left out, the markers are text like any other', () {
      const plain = MarkdownRichTextCodec(
        features: RichTextFeatures([ParagraphFeature()]),
      );

      final runs = runsOf(plain, '++Lundi++');

      expect(runs.single.text, '++Lundi++');
      expect(underlines(runs.single), isFalse);
    });
  });
}
