/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

/// What the package cannot do for a block holding no text of its own — a
/// picture, a table, a divider.
///
/// It walks a block's delta to move a caret sideways and to take a line into
/// the one above it, and these blocks have none. Not one of these is any
/// feature's: they are what an editor does with a block selected whole, so they
/// are the editor's own and hold whichever blocks are turned on.
List<CommandShortcutEvent> get wholeBlockCommands => [
  stepLeftCommand,
  stepRightCommand,
  stepToLineStartCommand,
  stepToLineEndCommand,
  deleteEmptyBlockCommand,
];

/// Steps the caret over a block that holds no text.
///
/// The package walks a block's delta to move a caret sideways, and a picture
/// has none: `moveHorizontal` falls through to the position it started from, so
/// a caret that reached a picture stayed on it and no amount of pressing left
/// or right brought it back to the words. Up and down worked all along — they
/// are worked out from rectangles, not from a delta, which is what made the
/// two behave differently.
///
/// One stop for the whole block, which is what a picture is: arriving on it
/// from either side and pressing on lands in the text beyond it.
KeyEventResult _step(EditorState editorState, {required bool forward}) {
  final selection = editorState.selection;

  if (selection == null || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  final node = editorState.getNodeAtPath(selection.end.path);

  // Only a block with nothing to walk through. Everything else the package
  // moves through correctly, and taking the key from it would break it.
  if (node == null || node.delta != null) {
    return KeyEventResult.ignored;
  }

  final target = forward
      ? node.next?.selectable?.start()
      : node.previous?.selectable?.end();

  if (target == null) {
    return KeyEventResult.ignored;
  }

  editorState.updateSelectionWithReason(
    Selection.collapsed(target),
    reason: SelectionUpdateReason.uiEvent,
  );

  return KeyEventResult.handled;
}

final stepRightCommand = CommandShortcutEvent(
  key: 'step over a block that holds no text, to the right',
  getDescription: () => 'Move the caret past a block holding no text',
  command: 'arrow right',
  handler: (editorState) => _step(editorState, forward: true),
);

final stepLeftCommand = CommandShortcutEvent(
  key: 'step over a block that holds no text, to the left',
  getDescription: () => 'Move the caret back past a block holding no text',
  command: 'arrow left',
  handler: (editorState) => _step(editorState, forward: false),
);

/// The same step for the keys that go to either end of the line.
///
/// A block holding no text has no line to go to the end of, and the package
/// reads that as a case it was never written for: `UnimplementedError` in the
/// console on every press, once the caret had reached a table.
final stepToLineStartCommand = CommandShortcutEvent(
  key: 'step back past a block that holds no text',
  getDescription: () => 'Move the caret back past a block holding no text',
  command: 'home',
  macOSCommand: 'cmd+arrow left',
  handler: (editorState) => _step(editorState, forward: false),
);

final stepToLineEndCommand = CommandShortcutEvent(
  key: 'step on past a block that holds no text',
  getDescription: () => 'Move the caret past a block holding no text',
  command: 'end',
  macOSCommand: 'cmd+arrow right',
  handler: (editorState) => _step(editorState, forward: true),
);

/// Deletes the empty block standing under a block that holds no text.
///
/// Backspace takes a line into the one above by merging its text with that
/// block's, so where the block above holds none the package gives up: the empty
/// line left under a table could not be deleted by any means.
///
/// Only an empty line. One with something written in it is the package's to
/// merge, and it declines that for a table on purpose — a table is deleted from
/// its own menu, never by the line under it.
final deleteEmptyBlockCommand = CommandShortcutEvent(
  key: 'delete an empty block under one that holds no text',
  getDescription: () => 'Delete the empty line under a block holding no text',
  command: 'backspace, shift+backspace',
  handler: _deleteEmptyBlock,
);

KeyEventResult _deleteEmptyBlock(EditorState editorState) {
  final selection = editorState.selection;

  if (selection == null ||
      !selection.isCollapsed ||
      selection.start.offset != 0) {
    return KeyEventResult.ignored;
  }

  final node = editorState.getNodeAtPath(selection.start.path);
  final delta = node?.delta;

  if (node == null ||
      delta == null ||
      delta.isNotEmpty ||
      node.children.isNotEmpty) {
    return KeyEventResult.ignored;
  }

  final previous = node.previous;

  if (previous == null || previous.delta != null) {
    return KeyEventResult.ignored;
  }

  // Back into what the block above holds, which for a table is its last cell.
  // One holding no text at all — a picture, a divider — is selected whole
  // instead, so that pressing again deletes it.
  final landing = _lastText(previous);
  final transaction = editorState.transaction
    ..deleteNode(node)
    ..afterSelection = landing == null
        ? Selection.single(path: previous.path, startOffset: 0, endOffset: 1)
        : Selection.collapsed(
            Position(path: landing.path, offset: landing.delta?.length ?? 0),
          );

  editorState.apply(transaction);

  return KeyEventResult.handled;
}

/// The last block under [node] holding text, however deep it sits.
Node? _lastText(Node node) {
  for (final child in node.children.reversed) {
    final text = child.delta != null ? child : _lastText(child);

    if (text != null) {
      return text;
    }
  }

  return null;
}
