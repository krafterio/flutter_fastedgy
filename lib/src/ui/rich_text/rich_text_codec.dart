/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

import 'rich_text_feature.dart';
import 'rich_text_nesting.dart';

/// How a document is stored and read back — the two directions always together,
/// so a format can never be taught to write something it cannot read.
///
/// Pick the one the field holds: [MarkdownRichTextCodec] where the text has to
/// stay readable and editable elsewhere, [JsonRichTextCodec] where it only has
/// to come back exactly as it went.
abstract class RichTextCodec {
  const RichTextCodec();

  String encode(Document document);

  /// Never returns a blockless document. The decoders drop what they cannot
  /// read, and a document with no block renders as a dead zone — nothing to
  /// click, nothing to type into, not even a placeholder. A blank paragraph
  /// keeps the page usable whatever was stored.
  Document decode(String? source);

  /// What an empty field, or one nothing could be read from, opens on.
  static Document get blank => Document.blank(withInitialText: true);
}

/// Markdown: readable by anything, but only carries what a feature taught it.
class MarkdownRichTextCodec extends RichTextCodec {
  final RichTextFeatures features;

  /// Required, and deliberately: what a codec can carry is what the caller
  /// listed. A default would mean a different round trip in each application
  /// that supplies a different set, and a mention or an image would come back
  /// as nothing with no error anywhere. Pass `RichTextFeatures([])` for the
  /// plain markdown the editor knows on its own.
  const MarkdownRichTextCodec({required this.features});

  /// One block per chunk, children indented under their parent: markdown nests
  /// nothing but list items, and the package flattens what it cannot nest into
  /// the text of the block above (see [encodeNestedMarkdown]).
  @override
  String encode(Document document) => encodeNestedMarkdown(
    features.beforeMarkdown(document),
    (block) => documentToMarkdown(
      Document.blank()..insert([0], [block]),
      customParsers: features.markdownEncoders,
    ).trimRight(),
  );

  @override
  Document decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return RichTextCodec.blank;
    }

    final nodes = decodeNestedMarkdown(
      source,
      (markdown) => markdownToDocument(
        markdown,
        markdownParsers: features.markdownDecoders,
      ).root.children.toList(),
    );

    if (nodes.isEmpty) {
      return RichTextCodec.blank;
    }

    final document = features.afterMarkdown(
      Document.blank()..insert([0], nodes),
    );

    return document.root.children.isEmpty ? RichTextCodec.blank : document;
  }
}

/// The node tree as it stands: lossless, and carries any block without the
/// features having to teach it one. Not meant to be read by a human.
class JsonRichTextCodec extends RichTextCodec {
  const JsonRichTextCodec();

  @override
  String encode(Document document) => jsonEncode(document.toJson());

  @override
  Document decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return RichTextCodec.blank;
    }

    final Document document;
    try {
      document = Document.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } catch (_) {
      return RichTextCodec.blank;
    }

    return document.root.children.isEmpty ? RichTextCodec.blank : document;
  }
}
