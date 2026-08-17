/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;
import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show getLogger, t;

import 'rich_text_codec.dart';
import 'rich_text_feature.dart';

final _log = getLogger('rich_text_paste');

/// Reads the picture at [url], or answers null when it cannot be had.
typedef RichTextImageFetch = Future<Uint8List?> Function(String url);

/// What a picture may weigh before it is left where it lives.
///
/// An inlined picture travels inside the text until a save stores it, so a
/// large one is carried through every keystroke's comparison and every draft.
const _maxInlineImageBytes = 10 * 1024 * 1024;

const _fetchTimeout = Duration(seconds: 15);

/// What says a piece of text was written as markdown rather than typed.
///
/// Split by line kind on purpose. A block marker only means anything at the
/// start of a line, and a single pasted line that happens to open with `#` is
/// far more often a comment or a tag than a heading — so those count only where
/// there are lines to structure. What a marked span is cannot be mistaken for
/// anything else, and counts wherever it appears.
final _blockMarkers = [
  RegExp(r'^ {0,3}#{1,6} \S', multiLine: true),
  RegExp(r'^ {0,3}[-*+] +\S', multiLine: true),
  RegExp(r'^ {0,3}\d+[.)] +\S', multiLine: true),
  RegExp(r'^ {0,3}> ?\S', multiLine: true),
  RegExp(r'^ {0,3}(```|~~~)', multiLine: true),
  RegExp(r'^ {0,3}([-*_] *){3,}$', multiLine: true),
  RegExp(r'^ {0,3}\|.*\|', multiLine: true),
];

final _spanMarkers = [
  RegExp(r'!\[[^\]]*\]\([^)\s]+\)'),
  RegExp(r'(?<!!)\[[^\]]+\]\([^)\s]+\)'),
  RegExp(r'\*\*[^*\n]+\*\*'),
  RegExp(r'~~[^~\n]+~~'),
  RegExp('`[^`\n]+`'),
];

/// Whether [text] reads as markdown, and so deserves to arrive as blocks rather
/// than as the characters it is made of.
bool looksLikeMarkdown(String text) {
  if (text.trim().isEmpty) {
    return false;
  }

  if (_spanMarkers.any((marker) => marker.hasMatch(text))) {
    return true;
  }

  return text.contains('\n') &&
      _blockMarkers.any((marker) => marker.hasMatch(text));
}

/// Puts [text] into the document as the blocks it describes, and answers
/// whether it was markdown at all — a plain paste is the caller's to make.
///
/// The pictures it names are brought along: a remote one is fetched and carried
/// inline, which is what turns it into an attachment of the record on the next
/// save. One that cannot be had is left pointing where it pointed.
Future<bool> pasteMarkdown(
  EditorState editorState,
  String text, {
  required RichTextFeatures features,
  RichTextImageFetch? fetchImage,
}) async {
  if (!looksLikeMarkdown(text)) {
    return false;
  }

  final nodes = MarkdownRichTextCodec(features: features)
      .decode(text)
      .root
      .children
      .toList();

  if (nodes.isEmpty) {
    return false;
  }

  await _inlineImages(nodes, fetchImage ?? fetchInlineImage);

  final single = nodes.length == 1 ? nodes.first : null;

  if (single != null && single.delta != null) {
    await editorState.pasteSingleLineNode(single);
  } else if (single != null) {
    await _insertBlocks(editorState, [single]);
  } else {
    await editorState.pasteMultiLineNodes(nodes);
  }

  return true;
}

/// Pastes what the clipboard holds: markdown as blocks where it is markdown,
/// and what the package does with plain text where it is not.
Future<void> pasteRichText(
  EditorState editorState, {
  required RichTextFeatures features,
  RichTextImageFetch? fetchImage,
}) async {
  final text = (await AppFlowyClipboard.getData()).text;

  if (text == null || text.isEmpty) {
    return;
  }

  final pasted = await pasteMarkdown(
    editorState,
    text,
    features: features,
    fetchImage: fetchImage,
  );

  if (!pasted) {
    handlePastePlainText(editorState, text);
  }
}

/// Paste, reading markdown as the blocks it describes.
///
/// Stands ahead of the package's own so it sees the clipboard first; anything
/// that is not markdown goes on to be pasted as plain text, unchanged.
CommandShortcutEvent richTextPasteCommand({
  required RichTextFeatures features,
  RichTextImageFetch? fetchImage,
}) => CommandShortcutEvent(
  key: 'paste markdown as blocks',
  getDescription: () => t('Paste, reading markdown as blocks'),
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: (editorState) {
    if (editorState.selection == null) {
      return KeyEventResult.ignored;
    }

    unawaited(
      pasteRichText(editorState, features: features, fetchImage: fetchImage),
    );

    return KeyEventResult.handled;
  },
);

/// A block holding no text of its own — a picture, a table — pasted on its own.
///
/// The package merges what it pastes into the block the caret sits in, which a
/// block with no delta cannot be merged into: it lands beside it instead, in
/// the place of an empty paragraph where there is one.
Future<void> _insertBlocks(EditorState editorState, List<Node> nodes) async {
  final selection = await editorState.deleteSelectionIfNeeded();

  if (selection == null) {
    return;
  }

  final at = selection.end.path;
  final node = editorState.getNodeAtPath(at);
  final replaceable =
      node != null &&
      node.type == ParagraphBlockKeys.type &&
      (node.delta?.isEmpty ?? true);
  final path = replaceable ? at : at.next;
  final transaction = editorState.transaction..insertNodes(path, nodes);

  if (replaceable) {
    transaction.deleteNode(node);
  }

  transaction.afterSelection = Selection.collapsed(Position(path: path));

  await editorState.apply(transaction);
}

/// Brings the pictures the pasted markdown names into the document itself.
Future<void> _inlineImages(List<Node> nodes, RichTextImageFetch fetch) async {
  final images = <Node>[];

  void walk(Node node) {
    if (node.type == ImageBlockKeys.type) {
      images.add(node);
    }

    node.children.forEach(walk);
  }

  nodes.forEach(walk);

  // Together rather than one after the other: a page of pictures would
  // otherwise hold the paste for as long as they take end to end.
  await Future.wait([
    for (final image in images)
      if (image.attributes[ImageBlockKeys.url] case final String url
          when _isRemote(url))
        _inlineImageOf(url, fetch).then((inlined) {
          if (inlined != null) {
            image.updateAttributes({ImageBlockKeys.url: inlined});
          }
        }),
  ]);
}

bool _isRemote(String url) =>
    url.startsWith('http://') || url.startsWith('https://');

Future<String?> _inlineImageOf(String url, RichTextImageFetch fetch) async {
  final bytes = await fetch(url);

  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  return 'data:${_mimeOf(url, bytes)};base64,${base64Encode(bytes)}';
}

/// What the picture is, read from its own first bytes rather than from the
/// address it came from: an address says nothing about what it serves, and the
/// server stores what the data URI claims.
String _mimeOf(String url, Uint8List bytes) {
  if (bytes.length >= 4) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50) {
      return 'image/png';
    }

    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }

    if (bytes[0] == 0x47 && bytes[1] == 0x49) {
      return 'image/gif';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[8] == 0x57) {
      return 'image/webp';
    }
  }

  return url.toLowerCase().endsWith('.svg') ? 'image/svg+xml' : 'image/png';
}

/// Fetches a pasted picture, on a client of its own.
///
/// Of its own deliberately: the address comes from whatever was copied, and the
/// application's client carries the session's token — which has no business
/// being sent to a host somebody else chose.
Future<Uint8List?> fetchInlineImage(String url) async {
  try {
    final response = await Dio(
      BaseOptions(
        responseType: ResponseType.bytes,
        connectTimeout: _fetchTimeout,
        receiveTimeout: _fetchTimeout,
        maxRedirects: 3,
        validateStatus: (status) => status != null && status < 400,
      ),
    ).get<List<int>>(url);

    final type = response.headers.value('content-type') ?? '';

    if (type.isNotEmpty && !type.startsWith('image/')) {
      return null;
    }

    final bytes = response.data;

    if (bytes == null || bytes.length > _maxInlineImageBytes) {
      return null;
    }

    return Uint8List.fromList(bytes);
  } catch (error, stackTrace) {
    _log.info('Failed to fetch a pasted image', error, stackTrace);

    return null;
  }
}
