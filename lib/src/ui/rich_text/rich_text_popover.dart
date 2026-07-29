/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:math' show max;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'rich_text_style.dart';
import 'rich_text_theme.dart';

/// Width every editing card shares, so the ones a document offers line up.
const richTextPopoverWidth = 320.0;

/// Breathing room between the card and what it is anchored to.
const _gap = 6.0;

/// Builds the body of a card, given the callback that closes it.
typedef RichTextPopoverBuilder =
    Widget Function(BuildContext context, VoidCallback dismiss);

/// Opens a card anchored to [selection], for a feature that edits something in
/// place — a link today, whatever comes next.
///
/// Takes care of what every such card needs and none of them should repeat:
/// placement against the selection and the floating toolbar, the chrome, click
/// outside and Escape to close, and holding the editor's focus while it is up
/// so the selection it acts on survives.
///
/// [width] and [height] override the shared size where a feature needs its own
/// — a wider card, or one that has to be told how tall it is rather than take
/// the height of what it holds.
///
/// Returns whether it opened: there is nothing to anchor to before the
/// selection has been laid out.
bool showRichTextPopover(
  BuildContext context,
  EditorState editorState,
  Selection selection, {
  required RichTextPopoverBuilder builder,
  double width = richTextPopoverWidth,
  double? height,
}) {
  final rects = editorState.selectionRects();
  final editorBox = editorState.renderBox;

  if (rects.isEmpty || editorBox == null) {
    return false;
  }

  final layout = RichTextPopoverLayout(
    selection: rects.first,
    editor: editorBox.localToGlobal(Offset.zero) & editorBox.size,
    width: width,
    height: height,
  );

  final overlayState = Overlay.of(context, rootOverlay: true);

  // The card is built inside an OverlayEntry, which is not under the caller —
  // an ambient theme simply is not found there. Captured here and re-applied
  // below, which is what InheritedTheme exists for.
  final themes = InheritedTheme.capture(
    from: context,
    to: overlayState.context,
  );

  OverlayEntry? overlay;

  // What held the focus before the card took it - the editor, as a rule, which
  // is keeping its selection for the card to act on.
  final held = FocusManager.instance.primaryFocus;

  void dismiss() {
    keepEditorFocusNotifier.decrease();
    overlay?.remove();
    overlay = null;

    if (held != null && held.context != null) {
      held.requestFocus();
    }
  }

  keepEditorFocusNotifier.increase();
  overlay = OverlayEntry(
    builder: (context) => themes.wrap(
      Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
            ),
          ),
          // Fills the overlay so the delegate lays the card out in the same
          // coordinates the selection rect is given in.
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: layout,
              child: _Card(
                width: width,
                height: height,
                onDismiss: dismiss,
                child: builder(context, dismiss),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  overlayState.insert(overlay!);

  return true;
}

class _Card extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  final double width;
  final double? height;

  const _Card({
    required this.child,
    required this.onDismiss,
    required this.width,
    this.height,
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  /// The card's own scope, taken as it opens.
  ///
  /// The editor holds the focus for as long as the card is up — that is what
  /// [keepEditorFocusNotifier] arranges, so the selection the card acts on
  /// survives. Nothing here would ever be autofocused then, and Escape would go
  /// to the editor, which answers it by dropping its selection and leaving the
  /// card standing. The scope claims the focus instead, and a field of the
  /// card's own is free to take it from there.
  ///
  /// Claimed a frame late: a scope that is not in the focus tree yet drops the
  /// request instead of holding it, unlike a plain node.
  final _scope = FocusScopeNode(debugLabel: 'rich text popover');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      // Above the scope, never inside it: a key reaches the node that holds the
      // focus and then rises through its ancestors.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        },
        child: FocusScope(
          node: _scope,
          child: Container(
            width: widget.width,
            height: widget.height,
            padding: const EdgeInsets.all(12),
            decoration: RichTextTheme.of(context).floatingSurface,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Places a card under the selected text, flipped above it when there is no
/// room below, kept inside the editor on both axes and always clear of the
/// floating toolbar.
///
/// A layout delegate rather than an offset computed up front: it is handed the
/// card's real size, so nothing about its height has to be guessed. Guessing
/// high would show up as slack between the card and the toolbar, guessing low
/// as the two overlapping.
@visibleForTesting
class RichTextPopoverLayout extends SingleChildLayoutDelegate {
  final Rect selection;
  final Rect editor;
  final double width;

  /// Left to the card's own content when null, which is the usual case — the
  /// delegate is handed the resulting height either way.
  final double? height;

  /// Whether to leave the floating toolbar room above the selection.
  ///
  /// The toolbar only ever shows over a *range*, so a surface that opens on the
  /// caret — the mention list, which opens on the trigger just typed — says no
  /// and sits against the line it belongs to instead of a toolbar's height
  /// away from it.
  final bool avoidToolbar;

  const RichTextPopoverLayout({
    required this.selection,
    required this.editor,
    this.width = richTextPopoverWidth,
    this.height,
    this.avoidToolbar = true,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(width, height ?? constraints.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = editor.right - childSize.width - _gap;
    final left = selection.left.clamp(
      editor.left + _gap,
      maxLeft > editor.left ? maxLeft : editor.left,
    );

    // The toolbar sits right above the selection, and drops below it when the
    // selection is too close to the top to fit — the same test it makes itself.
    final toolbarBelow =
        avoidToolbar && selection.top < RichTextStyle.toolbarHeight;
    final below =
        selection.bottom +
        _gap +
        (toolbarBelow ? RichTextStyle.toolbarSpan : 0);

    if (below + childSize.height <= editor.bottom) {
      return Offset(left, below);
    }

    final ceiling =
        selection.top -
        _gap -
        (avoidToolbar && !toolbarBelow ? RichTextStyle.toolbarHeight : 0);

    return Offset(left, max(0, ceiling - childSize.height));
  }

  @override
  bool shouldRelayout(RichTextPopoverLayout oldDelegate) =>
      oldDelegate.selection != selection ||
      oldDelegate.editor != editor ||
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.avoidToolbar != avoidToolbar;
}
