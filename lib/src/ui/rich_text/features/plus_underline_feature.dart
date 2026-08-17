/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../rich_text_feature.dart';

import 'package:markdown/markdown.dart' as md;

/// Reads `++text++` as underline — the spelling Quill and Fleather write, and
/// the one markdown-it gives to `ins`.
///
/// One-way on purpose, where a codec insists both directions travel together:
/// the package writes underline as `<u>` and goes on writing it that way. What
/// this adds is a second spelling *accepted* on the way in, so a field filled by
/// another editor reads as what it says instead of showing its markers — and
/// comes back written the one way the moment it is saved.
///
/// Only worth listing where such a field exists. An application that has always
/// written its markdown with this package has nothing to read that it did not
/// write itself.
class PlusUnderlineFeature extends RichTextFeature {
  const PlusUnderlineFeature();

  @override
  List<md.InlineSyntax> get markdownInlineSyntaxes => [_PlusUnderlineSyntax()];
}

class _PlusUnderlineSyntax extends md.InlineSyntax {
  _PlusUnderlineSyntax() : super(r'\+\+([^\n]+?)\+\+', startCharacter: 0x2B);

  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Markers glued to a word are the characters they look like: `C++ and C++`
  /// is a sentence about a language, not an underlined `and`. Written out
  /// rather than declined — the parser takes a syntax that matched as one that
  /// consumed, and one that consumed nothing would be tried here forever.
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final glued =
        match.start > 0 && _word.hasMatch(parser.source[match.start - 1]);

    parser.addNode(
      glued
          ? md.Text(match[0]!)
          : md.Element(
              'u',
              md.InlineParser(match[1]!, parser.document).parse(),
            ),
    );

    return true;
  }
}
