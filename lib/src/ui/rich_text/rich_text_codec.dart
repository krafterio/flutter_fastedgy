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
          _written,
        );

  /// One block written the way it will be read back.
  ///
  /// Markdown gives certain characters a meaning at the head of a line, and a
  /// paragraph somebody opened with `#` is written `\#` for it: without the
  /// backslash the words come back a heading the next time the document is
  /// opened, having been a paragraph on the screen the whole time it was
  /// written. The same goes for `-`, `>`, `1.`, a fence, a table row.
  ///
  /// Which characters those are is never listed anywhere, and deliberately: the
  /// block is written, read back and compared to itself. What survives is
  /// stored as it stands, what does not is escaped until it does. A syntax a
  /// feature teaches the decoder is therefore covered the day it is taught,
  /// including one nothing here has ever heard of.
  String _written(Node block) {
    final markdown = _markdown(block);
    final escapes = _escapes(block.delta?.toPlainText() ?? '').toList();

    // Nothing a backslash could go in front of is nothing that can be done
    // about it, whatever reading it back would say — and reading every block
    // back to find that out is not free.
    if (escapes.isEmpty || _readsBack(block, markdown)) {
      return markdown;
    }

    for (final offsets in escapes) {
      final escaped = _escapedAt(block, offsets);

      if (escaped == null) {
        continue;
      }

      final candidate = _markdown(escaped);

      if (_readsBack(block, candidate)) {
        return candidate;
      }
    }

    // Nothing that could be escaped brought it back whole. Storing it as it
    // stands is what happened before any of this, and reads at least right.
    return markdown;
  }

  String _markdown(Node block) => documentToMarkdown(
    Document.blank()..insert([0], [block]),
    customParsers: features.markdownEncoders,
  ).trimRight();

  /// Whether [markdown] read back is the block it was written from: one block,
  /// the same kind, the same shape, and the same words.
  ///
  /// The words as markdown leaves them, which is why the source is unescaped
  /// before the two are compared: a feature stores what it must escape already
  /// escaped — a mention's label carrying an `@` or a bracket — and the reader
  /// hands those back as the characters they stand for. Comparing the two
  /// literally would call every one of them a block gone wrong.
  ///
  /// What it does catch is a marker eaten: `> # x` comes back one quote, of the
  /// same shape, having quietly lost the dash on the way.
  bool _readsBack(Node block, String markdown) {
    final read = markdownToDocument(
      markdown,
      markdownParsers: features.markdownDecoders,
      inlineSyntaxes: features.markdownInlineSyntaxes,
    ).root.children;

    return read.length == 1 &&
        read.first.type == block.type &&
        read.first.children.length == block.children.length &&
        read.first.delta?.toPlainText() ==
            _unescaped(block.delta?.toPlainText() ?? '');
  }

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

/// What a backslash is allowed in front of in markdown, which is ASCII
/// punctuation and nothing else — before anything else it is just a backslash,
/// and `\1` escapes no more than the `1` did.
///
/// A rule of the format, not a list of what opens a block: what opens a block
/// is never written down here (see [MarkdownRichTextCodec._written]).
final _punctuation = RegExp(r'[\x21-\x2f\x3a-\x40\x5b-\x60\x7b-\x7e]');

/// A backslash that stands for the character behind it, rather than for
/// itself. What [_punctuation] is allowed in front of, read the other way.
final _escape = RegExp(r'\\([\x21-\x2f\x3a-\x40\x5b-\x60\x7b-\x7e])');

/// [text] as markdown will hand it back: the characters an escape stands for,
/// and the backslashes that stand for nothing left where they are.
String _unescaped(String text) =>
    text.replaceAllMapped(_escape, (match) => match[1]!);

final _blank = RegExp(r'\s');
final _nonBlank = RegExp(r'\S');

/// Where the backslashes could go, cheapest first: the first character markdown
/// would read something into, then every one of them in the opening word.
///
/// Two rounds and no more. One backslash is what `#`, `-`, `>` and `1.` take;
/// all of them is what a rule or a fence takes, being the same character three
/// times over. Anything still ambiguous after that is ambiguous.
Iterable<List<int>> _escapes(String text) sync* {
  final start = text.indexOf(_nonBlank);

  if (start < 0) {
    return;
  }

  final end = text.indexOf(_blank, start);
  final word = end < 0 ? text.length : end;
  final offsets = [
    for (var at = start; at < word; at++)
      if (_punctuation.hasMatch(text[at])) at,
  ];

  if (offsets.isEmpty) {
    return;
  }

  yield [offsets.first];

  if (offsets.length > 1) {
    yield offsets;
  }
}

/// [block] with a backslash written in at each of [offsets].
///
/// Null where they fall outside the first run of the text: what opens a line is
/// what the first run holds, and rewriting further than that would take the
/// marks off the words it was carrying.
Node? _escapedAt(Node block, List<int> offsets) {
  final delta = block.delta;
  final first = delta?.first;

  if (delta == null ||
      first is! TextInsert ||
      offsets.last >= first.text.length) {
    return null;
  }

  final buffer = StringBuffer();

  for (var at = 0; at < first.text.length; at++) {
    if (offsets.contains(at)) {
      buffer.write(r'\');
    }

    buffer.write(first.text[at]);
  }

  return block.copyWith(
    attributes: {
      ...block.attributes,
      blockComponentDelta: Delta(
        operations: [
          TextInsert(buffer.toString(), attributes: first.attributes),
          ...delta.skip(1),
        ],
      ).toJson(),
    },
  );
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
