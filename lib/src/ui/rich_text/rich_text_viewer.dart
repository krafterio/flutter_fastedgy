/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'rich_text_blocks.dart';
import 'rich_text_feature.dart';
import 'rich_text_style.dart';
import 'rich_text_theme.dart';

/// Renders a document, and nothing more: no editing, and none of the machinery
/// editing needs.
///
/// [RichTextEditor] with `editable: false` still mounts the whole editor — a
/// focus scope, an overlay, three service layers, a scroll controller — which
/// is fine once on a page and ruinous down a conversation. This is the other
/// end: a provider and a column of blocks.
///
/// It affords that because every block component reads exactly one thing from
/// its context, the [EditorState], and nothing from the services.
///
/// The blocks are the editor's own, through [richTextBlocks], so a code block
/// or a checkbox reads the same written or displayed.
///
/// The [editorState] is taken over: its renderer, its style and its read-only
/// flag are set here. Give each view its own rather than sharing one with an
/// editor.
class RichTextViewer extends StatefulWidget {
  final EditorState editorState;
  final RichTextFeatures features;
  final EdgeInsets padding;

  /// Null lets the blocks fill the width they are given.
  final double? maxWidth;

  /// The text the blocks are drawn at. Null takes the theme's page text; a
  /// message passes its field text so a thread reads at the app's body size.
  final TextStyle? textStyle;

  const RichTextViewer({
    required this.editorState,
    required this.features,
    super.key,
    this.padding = EdgeInsets.zero,
    this.maxWidth,
    this.textStyle,
  });

  @override
  State<RichTextViewer> createState() => _RichTextViewerState();
}

class _RichTextViewerState extends State<RichTextViewer> {
  @override
  void initState() {
    super.initState();
    widget.editorState.document.root.addListener(_onBlocksChanged);
  }

  /// Where the style is taken, rather than in [initState]: it is read from the
  /// theme, and an inherited widget cannot be depended on before this runs.
  /// A theme change lands here too, which is what makes the view follow it.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _adopt();
  }

  @override
  void didUpdateWidget(RichTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.editorState != widget.editorState) {
      oldWidget.editorState.document.root.removeListener(_onBlocksChanged);
      widget.editorState.document.root.addListener(_onBlocksChanged);
    }

    if (oldWidget.editorState != widget.editorState ||
        oldWidget.features != widget.features ||
        oldWidget.padding != widget.padding ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.textStyle != widget.textStyle) {
      _adopt();
    }
  }

  @override
  void dispose() {
    widget.editorState.document.root.removeListener(_onBlocksChanged);
    super.dispose();
  }

  /// A block added or removed under the root. What a block says of itself is
  /// its own component's business — it listens to its node — but the list of
  /// them is read here, so [applyRichTextDiff] would otherwise land unseen.
  void _onBlocksChanged() {
    if (mounted) setState(() {});
  }

  /// What the editor would otherwise set up on its own.
  void _adopt() {
    final theme = RichTextTheme.of(context);

    widget.editorState
      ..editable = false
      // The decorator comes with the style, never without it: a mention is
      // stored as one placeholder character and drawn by the decorator, so a
      // view mounted without it renders the mention as nothing at all.
      ..editorStyle = RichTextStyle.editor(
        theme,
        padding: widget.padding,
        maxWidth: widget.maxWidth,
        text: widget.textStyle,
        textSpanDecorator: widget.features.textSpanDecorator,
      )
      ..renderer = BlockComponentRenderer(
        builders: richTextBlocks(
          features: widget.features,
          listItemPadding: theme.listItemPadding,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Provider<EditorState>.value(
      value: widget.editorState,
      child: Builder(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final node in widget.editorState.document.root.children)
              Container(
                constraints: widget.maxWidth == null
                    ? null
                    : BoxConstraints(maxWidth: widget.maxWidth!),
                padding: widget.padding,
                child: widget.editorState.renderer.build(context, node),
              ),
          ],
        ),
      ),
    );
  }
}
