/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../rich_text_feature.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown has no empty paragraph: a blank line only separates blocks, so an
/// intentionally empty one is written as a non-breaking space and read back
/// from it.
const blankParagraphMarker = '&nbsp;';
const _nbsp = '\u00A0';

/// The plain paragraph, taught to keep the blank lines a writer typed.
class ParagraphFeature extends RichTextFeature {
  const ParagraphFeature();

  @override
  List<NodeParser> get markdownEncoders => const [_ParagraphNodeParser()];

  @override
  List<CustomMarkdownParser> get markdownDecoders => const [
    _BlankParagraphParser(),
  ];
}

class _ParagraphNodeParser extends TextNodeParser {
  const _ParagraphNodeParser();

  /// Stands alone between two blank lines.
  ///
  /// Closing on one keeps the next paragraph a paragraph of its own: a single
  /// newline is a soft break, which merged two into one. Opening on one keeps
  /// this paragraph out of the block above it: a quote or a list item swallows
  /// the line that follows it — markdown's lazy continuation — so a blank line
  /// written right under a quote was read as part of the quote and lost.
  ///
  /// Only top-level paragraphs: a blank line inside a list turns it loose, and
  /// the package then reads no text from its items.
  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final isBlank = (node.delta?.isEmpty ?? true) && node.children.isEmpty;
    final body = isBlank
        ? '$blankParagraphMarker\n'
        : super.transform(node, encoder);
    final standsAlone =
        node.previous != null && node.parent?.type == PageBlockKeys.type;

    return '${standsAlone ? '\n' : ''}$body\n';
  }
}

class _BlankParagraphParser extends CustomMarkdownParser {
  const _BlankParagraphParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element ||
        element.tag != 'p' ||
        element.textContent != _nbsp) {
      return [];
    }

    return [paragraphNode()];
  }
}
