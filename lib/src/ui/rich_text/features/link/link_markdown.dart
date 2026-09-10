/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

/// Drops the href of a run that links to its own text, so it is written bare.
///
/// `[https://kascade.io](https://kascade.io)` and `https://kascade.io` are read
/// back as the very same document — markdown autolinks a plain URL — so the
/// long form carries nothing but noise into a field people and the agent read.
Document withoutSelfLinks(Document document) {
  // Through JSON: the node tree hands out its attribute maps by reference, and
  // the document being written is the one open in the editor.
  final json =
      jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>;

  _strip(json['document']);

  return Document.fromJson(json);
}

/// Whether a run and its href are the same address, however its letters were
/// spelt.
///
/// A URL is kept as it was typed and linked as a browser reads it, so
/// `https://a.fr/décoration` carries an href of `https://a.fr/d%C3%A9coration`
/// and the two are one address. Compared letter for letter, a link on its own
/// address is not seen as one: it is written back as `[text](href)`, and a URL
/// already stored percent encoded comes out encoded once more each save —
/// `%C3%A9` then `%25C3%25A9` — so the link somebody wrote rots one save at a
/// time.
///
/// Decoded until it stops changing, because the two sides are not always
/// encoded the same number of times: what the markdown holds is read as it was
/// written, and the href the parser builds from it is escaped again.
bool _sameAddress(Object? text, Object? href) {
  if (text is! String || href is! String) {
    return false;
  }

  return text == href || _plain(text) == _plain(href);
}

String _plain(String address) {
  var seen = address;

  // Bounded: a string of percent signs decodes for as long as it is fed.
  for (var pass = 0; pass < 4; pass++) {
    final String decoded;

    try {
      decoded = Uri.decodeFull(seen);
    } on ArgumentError {
      return seen;
    }

    if (decoded == seen) {
      return seen;
    }

    seen = decoded;
  }

  return seen;
}

/// Gives an autolinked run back the address it was written with.
///
/// `package:markdown` renders a bare URL as HTML, and escapes it on the way:
/// `%C3%A9` comes back `%25C3%25A9`, so the run no longer links to its own text
/// and the document holds an address nobody wrote. Read back here, before
/// anything is drawn or written.
Document withReadableSelfLinks(Document document) {
  final json =
      jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>;

  _readable(json['document']);

  return Document.fromJson(json);
}

void _readable(Object? node) {
  if (node is! Map) {
    return;
  }

  final delta = node['data'] is Map ? (node['data'] as Map)['delta'] : null;

  if (delta is List) {
    for (final operation in delta) {
      if (operation is! Map) {
        continue;
      }

      final attributes = operation['attributes'];

      if (attributes is! Map) {
        continue;
      }

      final href = attributes[AppFlowyRichTextKeys.href];
      final text = operation['insert'];

      if (href != text && _sameAddress(text, href)) {
        attributes[AppFlowyRichTextKeys.href] = text;
      }
    }
  }

  final children = node['children'];

  if (children is List) {
    children.forEach(_readable);
  }
}

void _strip(Object? node) {
  if (node is! Map) {
    return;
  }

  // A node serialises its attributes under `data`, its delta inside them.
  final delta = node['data'] is Map ? (node['data'] as Map)['delta'] : null;

  if (delta is List) {
    for (final operation in delta) {
      if (operation is! Map) {
        continue;
      }

      final attributes = operation['attributes'];

      if (attributes is! Map ||
          !_sameAddress(
            operation['insert'],
            attributes[AppFlowyRichTextKeys.href],
          )) {
        continue;
      }

      attributes.remove(AppFlowyRichTextKeys.href);

      if (attributes.isEmpty) {
        operation.remove('attributes');
      }
    }
  }

  final children = node['children'];

  if (children is List) {
    children.forEach(_strip);
  }
}
