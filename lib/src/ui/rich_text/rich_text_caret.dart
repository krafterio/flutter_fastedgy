/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

/// Adds the paragraph a caret needs where the document holds none — under a
/// picture that ends it, over one that opens it — and takes it back the moment
/// the caret leaves it with nothing written in it.
///
/// Taken back because it is not an edit: a tap beside a picture is asking to
/// write, not writing, and a document left with a blank line at the end of it
/// reads as unsaved work to whoever compares it with what was stored.
Future<void> addParagraphForCaret(EditorState editorState, Path path) async {
  await editorState.apply(
    editorState.transaction
      ..insertNode(path, paragraphNode())
      ..afterSelection = Selection.collapsed(Position(path: path)),
  );

  final node = editorState.getNodeAtPath(path);

  if (node == null) {
    return;
  }

  final notifier = editorState.selectionNotifier;
  late final VoidCallback watch;

  watch = () {
    if (_isWritten(editorState, node)) {
      notifier.removeListener(watch);

      return;
    }

    if (editorState.selection?.start.path.equals(node.path) ?? false) {
      return;
    }

    notifier.removeListener(watch);

    // After the frame: the selection that ends the paragraph's life is often
    // the one a transaction just set, and another cannot be applied inside it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_drop(editorState, node)),
    );
  };

  notifier.addListener(watch);
}

/// Whether the paragraph became one of the document's own — written in, or
/// already gone by another hand.
bool _isWritten(EditorState editorState, Node node) =>
    editorState.getNodeAtPath(node.path) != node ||
    !(node.delta?.isEmpty ?? false) ||
    node.children.isNotEmpty;

Future<void> _drop(EditorState editorState, Node node) async {
  if (_isWritten(editorState, node)) {
    return;
  }

  final path = node.path;
  final selection = editorState.selection;
  final transaction = editorState.transaction..deleteNode(node);

  transaction.afterSelection = selection == null
      ? null
      : Selection(
          start: _shift(selection.start, path),
          end: _shift(selection.end, path),
        );

  await editorState.apply(transaction);
}

/// Where [position] lands once the block at [removed] is gone: the blocks that
/// followed it under the same parent each move up one.
Position _shift(Position position, Path removed) {
  final path = position.path;
  final depth = removed.length - 1;

  if (path.length <= depth ||
      !path.sublist(0, depth).equals(removed.sublist(0, depth)) ||
      path[depth] <= removed[depth]) {
    return position;
  }

  return Position(path: [...path]..[depth] -= 1, offset: position.offset);
}
