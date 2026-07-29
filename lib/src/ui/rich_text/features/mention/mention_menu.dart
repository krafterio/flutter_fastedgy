/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import '../../rich_text_controls.dart';
import '../../rich_text_popover.dart';
import '../../rich_text_theme.dart';
import 'mention_controller.dart';
import 'mention_source.dart';

/// Width of the suggestion list, and how tall it grows before it scrolls.
const _width = 300.0;
const _maxHeight = 260.0;

/// What a row is written at, from the text of the editor it was opened from: a
/// page offers its suggestions at a page's size, a field at a field's, and
/// neither has to say so.
TextStyle menuLabel(TextStyle text) =>
    text.copyWith(fontWeight: FontWeight.w500, height: 1.3);

/// A step under the label, the way a caption sits under a line everywhere else.
TextStyle menuSubtitle(TextStyle text) =>
    text.copyWith(fontSize: (text.fontSize ?? 14) - 2, height: 1.3);

/// A code standing for a record, drawn the way the theme draws one everywhere
/// else: monospaced, a step down, and quiet — it is recognised, not read.
TextStyle menuReference(TextStyle text, RichTextTheme theme) => text.copyWith(
  fontFamily: theme.monoFontFamily,
  fontSize: (text.fontSize ?? 14) - 2,
  fontWeight: FontWeight.w400,
  height: 1.3,
);

/// Puts the suggestion list under the trigger and keeps it there until the
/// controller says the hunt is over.
///
/// Deliberately focus-free, unlike every other floating surface of the editor:
/// the query is typed into the document, so the caret has to stay exactly where
/// it is. The list only watches, and answers to the keys the feature forwards.
void showMentionMenu(
  BuildContext context,
  MentionController controller,
  EditorState editorState,
) {
  final editorBox = editorState.renderBox;
  final anchor = controller.anchor;

  if (editorBox == null || anchor == null) {
    return;
  }

  final editor = editorBox.localToGlobal(Offset.zero) & editorBox.size;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);

  if (overlay == null) {
    return;
  }

  OverlayEntry? entry;

  void onChanged() {
    if (controller.isOpen) {
      entry?.markNeedsBuild();

      return;
    }

    controller.removeListener(onChanged);
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    // Nothing but the card catches a pointer — the layout box hit-tests its
    // child and nothing more — so a click in the document still reaches the
    // document, which is what closes the list.
    builder: (context) => Positioned.fill(
      child: CustomSingleChildLayout(
        // Opened on the caret, where no toolbar ever shows: the list sits
        // against the line being typed rather than a toolbar's height away.
        delegate: RichTextPopoverLayout(
          selection: anchor,
          editor: editor,
          width: _width,
          height: _maxHeight,
          avoidToolbar: false,
        ),
        child: _MentionMenu(
          controller: controller,
          textStyle: editorState.editorStyle.textStyleConfiguration.text,
        ),
      ),
    ),
  );

  controller.addListener(onChanged);
  overlay.insert(entry!);
}

class _MentionMenu extends StatelessWidget {
  final MentionController controller;

  /// The text of the editor the list was opened from, so what is offered reads
  /// at the size of what it will be written into.
  final TextStyle textStyle;

  const _MentionMenu({required this.controller, required this.textStyle});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isOpen) {
          return const SizedBox.shrink();
        }

        final candidates = controller.candidates;

        return _List(
          width: _width,
          children: candidates.isEmpty
              ? [
                  _Empty(
                    searching: controller.isSearching,
                    textStyle: textStyle,
                  ),
                ]
              : [
                  for (final (index, candidate) in candidates.indexed)
                    _Row(
                      candidate: candidate,
                      highlighted: index == controller.highlighted,
                      textStyle: textStyle,
                      onTap: () => unawaited(controller.write(candidate)),
                    ),
                ],
        );
      },
    );
  }
}

class _Row extends StatefulWidget {
  final MentionCandidate candidate;
  final bool highlighted;
  final TextStyle textStyle;
  final VoidCallback onTap;

  const _Row({
    required this.candidate,
    required this.highlighted,
    required this.textStyle,
    required this.onTap,
  });

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();

    // The list may open already scrolled — a query narrowed down to a name far
    // from the top — so the first highlight is revealed like any other.
    if (widget.highlighted) {
      _revealSoon();
    }
  }

  @override
  void didUpdateWidget(_Row oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.highlighted && !oldWidget.highlighted) {
      _revealSoon();
    }
  }

  /// After the frame that moved the highlight: the row is laid out by then, and
  /// the list may have been rebuilt around it.
  void _revealSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _reveal();
  });

  /// Scrolls the list just enough to show this row, and not at all when it is
  /// already whole on screen.
  ///
  /// Written out rather than left to [Scrollable.ensureVisible]: its policies
  /// scroll by a direction, and the highlight wraps around — a step down from
  /// the last suggestion lands on the first, which is up.
  void _reveal() {
    final box = context.findRenderObject() as RenderBox?;
    final position = Scrollable.maybeOf(context)?.position;

    if (box == null ||
        !box.attached ||
        position == null ||
        !position.hasContentDimensions) {
      return;
    }

    final viewport = RenderAbstractViewport.of(box);
    final atTop = viewport.getOffsetToReveal(box, 0).offset;
    final atBottom = viewport.getOffsetToReveal(box, 1).offset;

    final target = position.pixels < atBottom
        ? atBottom
        : position.pixels > atTop
        ? atTop
        : null;

    if (target != null) {
      position.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.candidate.subtitle;
    // A row whose label is a code reads the other way round: the name is what
    // it is read by, the code what it is recognised by.
    final reference =
        widget.candidate.labelShape == MentionLabelShape.reference;
    final theme = RichTextTheme.of(context);

    return RichTextControls.of(context).tappable(
      context,
      RichTextTapSpec(
        onTap: widget.onTap,
        active: widget.highlighted,
        radius: theme.chipRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              if (widget.candidate.leading case final leading?) ...[
                leading,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.candidate.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: reference
                          ? menuReference(widget.textStyle, theme)
                          : menuLabel(widget.textStyle),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: reference
                            ? menuLabel(widget.textStyle)
                            : menuSubtitle(widget.textStyle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing to offer: still looking, or nothing goes by that name.
class _Empty extends StatelessWidget {
  final bool searching;
  final TextStyle textStyle;

  const _Empty({required this.searching, required this.textStyle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          if (searching) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              searching ? t('Searching…') : t('Nothing goes by that name'),
              style: menuLabel(textStyle).copyWith(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card the candidates stand in: a floating surface that scrolls when the
/// list outgrows it, and nothing else. The rows are the application's.
class _List extends StatefulWidget {
  final double width;
  final List<Widget> children;

  const _List({required this.width, required this.children});

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  /// Its own, so the bar and the view are the same scrollable — and so the
  /// arrows have something to scroll when the highlight runs past the fold.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x00000000),
      child: Container(
        width: widget.width,
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        padding: const EdgeInsets.all(4),
        decoration: RichTextTheme.of(context).floatingSurface,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}
