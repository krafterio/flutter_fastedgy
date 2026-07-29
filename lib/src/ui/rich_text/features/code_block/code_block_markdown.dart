/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_block_component.dart';

/// Reads a fenced code block back into a [codeBlockNode].
///
/// The package encodes one (its `CodeBlockNodeParser` writes the fence) but its
/// decoder has no parser for it, and silently drops what no parser claims — so
/// a saved code block came back as nothing, and a description holding only one
/// reloaded as a document with zero blocks: an editor with nothing to click.
class MarkdownCodeBlockParser extends CustomMarkdownParser {
  const MarkdownCodeBlockParser();

  static const _languagePrefix = 'language-';

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') {
      return [];
    }

    md.Element? code;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        code = child;
        break;
      }
    }
    if (code == null) {
      return [];
    }

    final className = code.attributes['class'] ?? '';
    final language = className.startsWith(_languagePrefix)
        ? className.substring(_languagePrefix.length)
        : null;
    // The fence's closing newline belongs to the syntax, not to the code.
    final text = code.textContent.endsWith('\n')
        ? code.textContent.substring(0, code.textContent.length - 1)
        : code.textContent;

    return [codeBlockNode(delta: Delta()..insert(text), language: language)];
  }
}
