/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/ui.dart';

/// The shared markdown corpus: what the stored format says, written down.
///
/// `fixtures_generator_test.dart` writes it and `corpus_test.dart` holds this
/// package to it. The same files are copied into every other implementation of
/// the format, where the very same assertions are run on them. A fixture is
/// therefore never a snapshot of one implementation.
const String corpusDirectory = 'test/fixtures/markdown';

/// Written with the feature set an application actually mounts, `++text++`
/// included: what the corpus describes has to be what is really stored.
final MarkdownRichTextCodec corpusCodec = MarkdownRichTextCodec(
  features: defaultRichTextFeatures.and([const PlusUnderlineFeature()]),
);

/// The block vocabulary the corpus is written in, which is no implementation's
/// own: a fixture that took a side would stop being an arbiter.
const Map<String, String> neutralTypes = {
  'paragraph': 'paragraph',
  'heading': 'heading',
  'bulleted_list': 'bullet',
  'numbered_list': 'numbered',
  'todo_list': 'todo',
  'quote': 'quote',
  'divider': 'divider',
  'code': 'code',
  'image': 'image',
  'table': 'table',
};

/// Written out in this order on both sides, so two outlines compare literally.
const List<String> markOrder = ['bold', 'italic', 'underline', 'strikethrough', 'code'];

/// A document as the corpus describes it: what each block is, how deep it sits,
/// what it says, and how what it says is marked.
List<Map<String, Object?>> outlineOf(Document document) {
  final blocks = <Map<String, Object?>>[];

  void walk(Node node, int indent) {
    final runs = <Map<String, Object?>>[];

    for (final operation in node.delta ?? Delta()) {
      if (operation is! TextInsert) {
        continue;
      }

      final attributes = operation.attributes ?? const {};

      runs.add({
        't': operation.text,
        'm': [
          for (final key in markOrder)
            if (attributes[key] == true) key == 'strikethrough' ? 'strike' : key,
        ],
        'href': attributes[AppFlowyRichTextKeys.href],
      });
    }

    blocks.add({
      'type': neutralTypes[node.type] ?? node.type,
      'indent': indent,
      'attrs': {
        if (node.attributes[HeadingBlockKeys.level] != null) 'level': node.attributes[HeadingBlockKeys.level],
        if (node.attributes[TodoListBlockKeys.checked] != null) 'checked': node.attributes[TodoListBlockKeys.checked],
        if (node.attributes[CodeBlockKeys.language] != null) 'language': node.attributes[CodeBlockKeys.language],
      },
      'runs': runs,
    });

    for (final child in node.children) {
      walk(child, indent + 1);
    }
  }

  for (final node in document.root.children) {
    walk(node, 0);
  }

  return blocks;
}
