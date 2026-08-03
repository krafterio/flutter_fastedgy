/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'rich_text_action.dart';
import 'rich_text_clipboard.dart';
import 'rich_text_controls.dart';
import 'rich_text_theme.dart';

/// Cut, copy, paste and select all, drawn the way the platform draws them.
///
/// The editor is a document, not a field the system draws a callout for, and
/// the package it is built on wires a context menu on the desktop side alone —
/// so on a phone there was no way to paste at all, and the actions ended up on
/// the formatting strip, which is not where anybody looks for them.
///
/// One widget for both, and two directions: a row for the callout a held press
/// leaves over the selected words, a column for the menu a right-click opens.
/// What they offer is the same list, so the two cannot drift apart.
class RichTextClipboardMenu extends StatefulWidget {
  final EditorState editorState;

  final List<RichTextAction> actions;

  /// A row over the selection, or a column under the pointer.
  final Axis direction;

  /// Called once something has run, to take the surface away with it.
  final VoidCallback onDone;

  const RichTextClipboardMenu({
    required this.editorState,
    required this.actions,
    required this.onDone,
    super.key,
    this.direction = Axis.horizontal,
  });

  @override
  State<RichTextClipboardMenu> createState() => _RichTextClipboardMenuState();
}

/// All the room a row of these may claim before it starts sliding.
const _maxWidth = 300.0;

/// What one of these stands in, for whatever has to be placed clear of it.
///
/// A number rather than a measurement: it is needed to lay something else out,
/// which happens before this is built — and it is one row of one line of text,
/// so it does not vary.
const richTextCalloutHeight = 42.0;

class _RichTextClipboardMenuState extends State<RichTextClipboardMenu> {
  @override
  void initState() {
    super.initState();

    // What there is to paste decides whether one of these is live, and nobody
    // has asked since the last time a menu was up.
    unawaited(refreshRichTextClipboard());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: richTextClipboardHasContent,
      builder: (context, _, _) {
        final live = [
          for (final action in widget.actions)
            if (action.isEnabled(widget.editorState)) action,
        ];

        // Nothing to offer is nothing to draw: an empty callout is a white
        // sliver hanging off the words for no reason.
        if (live.isEmpty) {
          return const SizedBox.shrink();
        }

        if (widget.direction == Axis.vertical) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _items(live),
          );
        }

        // Four words are wider than a callout hanging off two: the row slides
        // rather than spilling out of the card, the way the system's own
        // paginates rather than growing.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: IntrinsicWidth(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _items(live),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _items(List<RichTextAction> actions) => [
    for (final action in actions)
      _RichTextClipboardItem(
        label: action.getLabel(),
        stretched: widget.direction == Axis.vertical,
        onTap: () {
          unawaited(action.run(widget.editorState));
          widget.onDone();
        },
      ),
  ];
}

class _RichTextClipboardItem extends StatelessWidget {
  final String label;

  /// A column's items take the width of the widest; a row's take their own.
  final bool stretched;

  final VoidCallback onTap;

  const _RichTextClipboardItem({
    required this.label,
    required this.stretched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return RichTextControls.of(context).tappable(
      context,
      RichTextTapSpec(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            textAlign: stretched ? TextAlign.left : TextAlign.center,
            style: TextStyle(color: theme.ink, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
