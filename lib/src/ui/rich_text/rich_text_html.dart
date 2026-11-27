/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

/// Markdown as the HTML that says the same, for wherever the text leaves the
/// application and is read by something else: the body of an email.
///
/// The markdown is the one the editor writes (GitHub flavoured: tables, task
/// lists, strikethrough). What it holds of raw HTML is written as text, never
/// carried through: the result only has the tags its markdown asked for.
String markdownToHtml(String? markdown) {
  if (markdown == null || markdown.trim().isEmpty) {
    return '';
  }

  return md
      .markdownToHtml(
        markdown,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: true,
        inlineSyntaxes: [_NoInlineHtml()],
        blockSyntaxes: const [_NoBlockHtml()],
      )
      .trim();
}

const _escape = HtmlEscape();

/// Reads a raw tag in the text as the characters it is made of.
class _NoInlineHtml extends md.InlineSyntax {
  _NoInlineHtml() : super(r'<[^>]*>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(_escape.convert(match[0]!)));

    return true;
  }
}

/// Reads a line opening a raw block as a paragraph of text.
class _NoBlockHtml extends md.BlockSyntax {
  const _NoBlockHtml();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}</?[a-zA-Z!?]');

  @override
  md.Node parse(md.BlockParser parser) {
    final line = parser.current.content;
    parser.advance();

    return md.Element('p', [md.Text(_escape.convert(line))]);
  }
}
