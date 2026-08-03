/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'rich_text_action.dart';
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

  final Widget child;

  const RichTextTouchMenu({
    required this.editorState,
    required this.scrollController,
    required this.features,
    required this.child,
    super.key,
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

  /// The top of the selection, where the toolbar points.
  final Offset anchor;

  final VoidCallback onDone;

  const _RichTextTouchCallout({
    required this.editorState,
    required this.features,
    required this.anchor,
    required this.onDone,
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
          anchors: TextSelectionToolbarAnchors(primaryAnchor: widget.anchor),
        );
      },
    );
  }
}
