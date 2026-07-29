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
          attributes[AppFlowyRichTextKeys.href] != operation['insert']) {
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
