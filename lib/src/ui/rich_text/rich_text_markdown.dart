/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'rich_text_codec.dart';
import 'rich_text_diff.dart';
import 'rich_text_feature.dart';
import 'rich_text_theme.dart';
import 'rich_text_view.dart';

/// Markdown drawn as the rich text it stands for.
///
/// [RichTextView] renders a document; this holds one for a caller that has only
/// the text — a message off the wire, a value an agent proposes to write.
///
/// Text arriving in pieces — an answer streaming in — is taken in as a diff
/// rather than decoded into a document of its own each time: the blocks that
/// did not change are left exactly where they stand, so an answer grows in
/// place instead of being built again on every token.
class RichTextMarkdown extends StatefulWidget {
  final String? markdown;

  /// What the markdown is read with, and what draws it — the same set both
  /// ways: a mention travels as a link, and only the decorator that comes with
  /// the features knows to draw it as a chip.
  final RichTextFeatures features;

  /// Null takes the theme's field text — a message reads at body size.
  final TextStyle? textStyle;

  /// Around each block, on top of what a block already keeps for itself.
  final EdgeInsets padding;

  const RichTextMarkdown({
    required this.markdown,
    required this.features,
    super.key,
    this.textStyle,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<RichTextMarkdown> createState() => _RichTextMarkdownState();
}

class _RichTextMarkdownState extends State<RichTextMarkdown> {
  /// Read from the widget rather than kept: the features are what the caller
  /// says they are on this build, and a codec built once from the first of them
  /// would go on reading the text with a set nobody asked for.
  MarkdownRichTextCodec get _codec =>
      MarkdownRichTextCodec(features: widget.features);

  late final EditorState _editorState;

  /// The text the document is showing.
  ///
  /// Compared against the widget's own rather than trusted from it: a diff
  /// lands a frame later, and whatever arrives while one is in flight is picked
  /// up by the run already going instead of starting a second one over the same
  /// document.
  ///
  /// Seeded in [initState], never through a field initializer: a `late` one
  /// runs on FIRST READ, which is inside the comparison below — it would take
  /// the text that has just arrived for the text already shown and conclude
  /// there was nothing to do.
  String? _shown;

  bool _adopting = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.markdown;
    _editorState = EditorState(document: _codec.decode(widget.markdown));
  }

  @override
  void didUpdateWidget(covariant RichTextMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.markdown != widget.markdown) {
      // Applying a transaction rebuilds the blocks, which is forbidden while
      // the frame that brought the new text is still building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_adopt());
      });
    }
  }

  Future<void> _adopt() async {
    if (_adopting) {
      return;
    }

    _adopting = true;

    try {
      while (mounted && _shown != widget.markdown) {
        final markdown = widget.markdown;
        await applyRichTextDiff(_editorState, _codec.decode(markdown));
        _shown = markdown;
      }
    } finally {
      _adopting = false;
    }
  }

  @override
  void dispose() {
    _editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RichTextView(
    editorState: _editorState,
    features: widget.features,
    textStyle: widget.textStyle ?? RichTextTheme.of(context).fieldText,
    padding: widget.padding,
  );
}
