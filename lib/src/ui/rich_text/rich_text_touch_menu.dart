/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'rich_text_action.dart';
import 'rich_text_action_bar.dart';
import 'rich_text_clipboard.dart';
import 'rich_text_clipboard_menu.dart' show richTextCalloutHeight;
import 'rich_text_feature.dart';

/// Cut, copy, paste and select all over a selection held under a thumb.
///
/// The editor is a document rather than a field, so the platform draws it no
/// callout of its own and the package wires one on the desktop side alone —
/// which left a phone with no way to paste at all.
///
/// Drawn by [AdaptiveTextSelectionToolbar], which is the toolbar the platform's
/// own text fields raise: the rounded dark bar with paging arrows on iOS, the
/// card on Android, in the system's wording and with its animations. Nothing
/// here decides how it looks — only what it offers.
///
/// [MobileFloatingToolbar] owns when it is up: it holds off while a selection
/// handle is being dragged, takes it away on a scroll and puts it back once
/// that settles, and raises it again on a tap inside words already selected.
class RichTextTouchMenu extends StatelessWidget {
  final EditorState editorState;

  final EditorScrollController scrollController;

  /// What a paste is folded back into, which the document decides.
  final RichTextFeatures features;

  /// How much room the formatting strip is taking, and which edge it took it
  /// on.
  ///
  /// Read for two things the package cannot know: when the words have moved
  /// under a menu already raised, and which side of them is free to put one on.
  final ValueListenable<double>? reserved;
  final RichTextToolbarEdge edge;

  final Widget child;

  const RichTextTouchMenu({
    required this.editorState,
    required this.scrollController,
    required this.features,
    required this.child,
    super.key,
    this.reserved,
    this.edge = RichTextToolbarEdge.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return MobileFloatingToolbar(
      editorState: editorState,
      editorScrollController: scrollController,
      floatingToolbarHeight: richTextCalloutHeight,
      toolbarBuilder: (context, anchor, close) => _RichTextTouchCallout(
        editorState: editorState,
        features: features,
        anchor: anchor,
        reserved: reserved,
        edge: edge,
        onDone: close,
      ),
      child: child,
    );
  }
}

/// What the platform's own text selection toolbar is handed to draw.
///
/// The same actions the right-click menu offers on the desktop side, filtered
/// the same way — cut and copy stand down over a bare caret, paste stands down
/// with an empty clipboard.
class _RichTextTouchCallout extends StatefulWidget {
  final EditorState editorState;

  final RichTextFeatures features;

  /// The top of the selection, where the toolbar points — as it was when the
  /// package raised this. Read again on every build (see [_RichTextTouchCalloutState._anchor]).
  final Offset anchor;

  /// What the formatting strip is taking, and on which edge.
  final ValueListenable<double>? reserved;
  final RichTextToolbarEdge edge;

  final VoidCallback onDone;

  const _RichTextTouchCallout({
    required this.editorState,
    required this.features,
    required this.anchor,
    required this.onDone,
    required this.edge,
    this.reserved,
  });

  @override
  State<_RichTextTouchCallout> createState() => _RichTextTouchCalloutState();
}

/// Ours to Flutter's, so the toolbar knows a paste from a copy — it orders and
/// draws them by type, and on iOS the paste is the one the system may answer
/// for itself.
const _types = <String, ContextMenuButtonType>{
  'cut': ContextMenuButtonType.cut,
  'copy': ContextMenuButtonType.copy,
  'paste': ContextMenuButtonType.paste,
  'select_all': ContextMenuButtonType.selectAll,
};

class _RichTextTouchCalloutState extends State<_RichTextTouchCallout> {
  @override
  void initState() {
    super.initState();

    // What there is to paste decides whether that one is offered, and nobody
    // has asked since the last time a menu was up.
    unawaited(refreshRichTextClipboard());
    widget.reserved?.addListener(_reanchor);
  }

  @override
  void didUpdateWidget(_RichTextTouchCallout old) {
    super.didUpdateWidget(old);

    if (old.reserved != widget.reserved) {
      old.reserved?.removeListener(_reanchor);
      widget.reserved?.addListener(_reanchor);
    }
  }

  @override
  void dispose() {
    widget.reserved?.removeListener(_reanchor);
    super.dispose();
  }

  /// A frame late, and it has to be: the room is reserved in the frame after
  /// this fires, and where the words end up is only known once it has been laid
  /// out. Reading them now would anchor this to where they were.
  void _reanchor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Where the selection stands *now*.
  ///
  /// The package anchors this once, on the frame it raises it, and the words
  /// move afterwards: the formatting strip going up reserves room at the foot
  /// of the content, and everything above it rises by that much. Read from the
  /// selection each time rather than carried, so the menu goes where the words
  /// went.
  Rect? get _words {
    final top = widget.editorState.renderBox?.localToGlobal(Offset.zero).dy;
    final rects = [
      for (final rect in widget.editorState.selectionRects())
        if (top == null || rect.top >= top) rect,
    ];

    return rects.isEmpty
        ? null
        : rects.reduce((lowest, rect) => rect.top < lowest.top ? rect : lowest);
  }

  /// Which side of the words the menu may take.
  ///
  /// Over them by preference, which is where every platform puts it — and under
  /// them where something of ours is already standing over them. A strip docked
  /// at the head of a field is exactly that, and the menu was drawn on top of
  /// it.
  ///
  /// Said by handing the room above as ending at the top of the screen, which
  /// is how a selection toolbar is told it does not fit there: it reads the
  /// anchor above as the whole of what it has to sit in.
  TextSelectionToolbarAnchors get _anchors {
    final words = _words;

    if (words == null) {
      return TextSelectionToolbarAnchors(primaryAnchor: widget.anchor);
    }

    final covered =
        widget.edge == RichTextToolbarEdge.top &&
        (widget.reserved?.value ?? 0) > 0;

    return TextSelectionToolbarAnchors(
      primaryAnchor: covered ? Offset(words.center.dx, 0) : words.topCenter,
      secondaryAnchor: words.bottomCenter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: richTextClipboardHasContent,
      builder: (context, _, _) {
        final items = <ContextMenuButtonItem>[
          for (final action in RichTextActions.clipboard(widget.features))
            if (action.isEnabled(widget.editorState))
              ContextMenuButtonItem(
                type: _types[action.id] ?? ContextMenuButtonType.custom,
                // The application's wording rather than the platform's: the
                // rest of the editor speaks in it, and it is translated
                // wherever the toolbar is not.
                label: action.getLabel(),
                onPressed: () {
                  unawaited(action.run(widget.editorState));
                  widget.onDone();
                },
              ),
        ];

        // Nothing to offer is nothing to draw, rather than a bar hanging off
        // the words with one empty row in it.
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        return AdaptiveTextSelectionToolbar.buttonItems(
          buttonItems: items,
          anchors: _anchors,
        );
      },
    );
  }
}
