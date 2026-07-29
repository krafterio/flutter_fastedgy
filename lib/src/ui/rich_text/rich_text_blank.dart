/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';

/// Whether [document] says nothing.
///
/// Read from the blocks, never from the markdown they encode to: an emptied
/// editor still holds one blank block, and a blank paragraph is written as a
/// non-breaking space — text as far as a trim is concerned.
///
/// A block that holds text and holds none is blank whatever kind of block it
/// is: `# ` on its own line turns a paragraph into a heading, and a heading
/// emptied of its words is as empty as the paragraph it was. A block with no
/// text to hold — a picture — is content, and so is one with children.
bool isRichTextBlank(Document document) => document.root.children.every(
  (node) =>
      node.children.isEmpty &&
      (node.delta?.toPlainText().trim().isEmpty ?? false),
);

/// Takes [editorState] back to the one blank paragraph a field opens on, the
/// caret in it.
///
/// Written out rather than diffed against a blank document: the diff leaves the
/// block holding the caret alone, on purpose (see `applyRichTextDiff`), and in
/// a field being typed into that block is the only one there is.
Future<void> clearRichText(EditorState editorState) async {
  final blocks = editorState.document.root.children.length;

  if (blocks == 0) {
    return;
  }

  await editorState.apply(
    editorState.transaction
      ..deleteNodesAtPath([0], blocks)
      ..insertNode([0], paragraphNode())
      ..afterSelection = Selection.collapsed(Position(path: [0])),
  );
}
