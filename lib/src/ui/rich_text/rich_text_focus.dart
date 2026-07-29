/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';

/// Puts the caret at the end of what [editorState] holds, and takes the focus
/// with it.
///
/// A rich text field has no focus node to ask: the editor claims the focus when
/// the selection moves for a UI reason, which is what this is — a composer
/// focused as its panel opens, clicked around rather than into, or written into
/// again once what was in it has been sent.
Future<void> focusRichText(EditorState editorState) async {
  final blocks = editorState.document.root.children;

  if (blocks.isEmpty) {
    return;
  }

  // The last block that holds text, not the last of the top level: a list is
  // one block with its items under it, and the caret belongs in the item.
  var node = blocks.last;

  while (node.children.isNotEmpty) {
    node = node.children.last;
  }

  await editorState.updateSelectionWithReason(
    Selection.collapsed(
      Position(path: node.path, offset: node.delta?.length ?? 0),
    ),
    reason: SelectionUpdateReason.uiEvent,
  );
}
