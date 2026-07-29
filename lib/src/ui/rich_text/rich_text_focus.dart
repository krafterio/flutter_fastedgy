/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

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

/// Holds the editor's caret while something the application opened has taken
/// the focus.
///
/// A surface that floats — the mention list, the block list, a card anchored to
/// a selection — is built without focus of its own, so the caret never moves
/// and nothing has to be held. A sheet or a dialog is a route: it takes the
/// focus outright, the editor is told it has lost it and lets its selection go,
/// and everything that was drawn from that selection goes with it — the grips
/// of the table being worked on, the gutter of the block, the strip of actions.
///
/// So it is not a table's problem, nor a menu's: it is what happens to any
/// document whenever an application opens one of its own surfaces over it. This
/// is what to wrap that surface's anchor in.
///
/// [open] is what the application answers with while its surface is up — the
/// `isOpen` a [RichTextMenuSpec] hands its anchor, as a rule.
class RichTextHoldsCaret extends StatefulWidget {
  final EditorState editorState;

  /// Whether something has the focus and the caret has to be held.
  final bool open;

  final Widget child;

  const RichTextHoldsCaret({
    required this.editorState,
    required this.open,
    required this.child,
    super.key,
  });

  @override
  State<RichTextHoldsCaret> createState() => _RichTextHoldsCaretState();
}

class _RichTextHoldsCaretState extends State<RichTextHoldsCaret> {
  /// Where the caret was when the surface opened, so it can be put back if the
  /// editor let it go anyway.
  Selection? _held;

  bool _holding = false;

  @override
  void didUpdateWidget(RichTextHoldsCaret oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.open == oldWidget.open) {
      return;
    }

    widget.open ? _hold() : _release();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _hold() {
    if (_holding) {
      return;
    }

    _holding = true;
    _held = widget.editorState.selection;
    keepEditorFocusNotifier.increase();
  }

  void _release() {
    if (!_holding) {
      return;
    }

    _holding = false;
    keepEditorFocusNotifier.decrease();

    final held = _held;
    _held = null;

    // Put back what was let go despite the hold: the notifier keeps the editor
    // from dropping its own selection, and says nothing about what a route
    // pushed over it may have done on the way out.
    if (held != null && widget.editorState.selection == null) {
      widget.editorState.selection = held;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
