/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

import 'rich_text_blank.dart';
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

  /// Empty for the document a cleared field is left in — the single blank
  /// block an editor opens on.
  ///
  /// A blank paragraph writes itself as a non-breaking space, which is how the
  /// blank lines somebody typed between two sentences survive the round trip.
  /// That is worth keeping, and worth not storing when it is *all* there is:
  /// a cleared field would come back holding a space, and every reader — a
  /// server, an agent, a list preview — would take it for content.
  String encode(Document document);

  /// Whether [document] is what a cleared field holds: nothing said, and no
  /// blank line deliberately left standing.
  static bool isCleared(Document document) =>
      document.root.children.length <= 1 && isRichTextBlank(document);

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
  String encode(Document document) => RichTextCodec.isCleared(document)
      ? ''
      : encodeNestedMarkdown(
          features.beforeMarkdown(_spaceOutsideMarks(document)),
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
        inlineSyntaxes: features.markdownInlineSyntaxes,
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
  String encode(Document document) =>
      RichTextCodec.isCleared(document) ? '' : jsonEncode(document.toJson());

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

/// What a mark is written with in markdown, and what a space next to it kills.
const _markKeys = {'bold', 'italic', 'underline', 'strikethrough', 'code'};

final _leading = RegExp(r'^\s+');
final _trailing = RegExp(r'\s+$');

/// Takes the blanks out of what is marked, and puts them back around it.
///
/// Markdown opens a mark on the character that follows it, and `** x**` opens
/// nothing at all: the parser wants a non-blank on the inside. Bold a run a
/// writer selected with the space before it — which is what a double tap gives
/// — and the markers land against that space, so the text comes back with its
/// stars in it and no bold anywhere. It reads as a broken editor, and it is the
/// round trip that is broken.
///
/// `**` around ` x ` becomes ` **x** `: the same words, the same emphasis, and
/// markdown able to say it.
Document _spaceOutsideMarks(Document document) {
  final json =
      jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>;

  void walk(Object? node) {
    if (node is! Map) {
      return;
    }

    final data = node['data'];
    final delta = data is Map ? data['delta'] : null;

    if (delta is List) {
      data['delta'] = [for (final operation in delta) ..._spaced(operation)];
    }

    final children = node['children'];

    if (children is List) {
      children.forEach(walk);
    }
  }

  walk(json['document']);

  return Document.fromJson(json);
}

/// One run as the blanks around its words leave it: up to three, and itself
/// when there is nothing to move.
List<Object?> _spaced(Object? operation) {
  if (operation is! Map ||
      operation['insert'] is! String ||
      operation['attributes'] is! Map) {
    return [operation];
  }

  final attributes = operation['attributes'] as Map;

  if (!attributes.keys.any(_markKeys.contains)) {
    return [operation];
  }

  final text = operation['insert'] as String;
  final lead = _leading.stringMatch(text) ?? '';
  final trail = text.length > lead.length
      ? _trailing.stringMatch(text) ?? ''
      : '';
  final core = text.substring(lead.length, text.length - trail.length);

  if (lead.isEmpty && trail.isEmpty) {
    return [operation];
  }

  // What the blanks keep: a link still covers them, a mark no longer does —
  // marking a space says nothing and costs a pair of markers.
  final around = {
    for (final entry in attributes.entries)
      if (!_markKeys.contains(entry.key)) entry.key: entry.value,
  };

  Map<String, Object?> run(String insert, Map<Object?, Object?> carried) => {
    'insert': insert,
    if (carried.isNotEmpty) 'attributes': carried,
  };

  return [
    if (lead.isNotEmpty) run(lead, around),
    if (core.isNotEmpty) run(core, attributes),
    if (trail.isNotEmpty) run(trail, around),
  ];
}
