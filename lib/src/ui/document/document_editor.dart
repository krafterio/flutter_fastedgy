/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'document_layout.dart';
import '../rich_text/rich_text_editor.dart';
import '../rich_text/rich_text_feature.dart';
import '../rich_text/rich_text_features.dart';
import 'document_gutter.dart';

/// A [RichTextEditor] given a page's manners: it owns the scrolling, centres
/// its blocks on a column, carries a header and a footer on that same column,
/// and hangs a gutter in each block's left margin to add or drag one.
///
/// This is the flow description and, later, a note. A field wanting rich text —
/// a composer, a reply box — takes the editor underneath directly.
class DocumentEditor extends StatefulWidget {
  final EditorState editorState;

  /// Rendered inside the editor's scroll view, above and below the blocks and
  /// on their column — the editor owns the page scrolling, its overlay needing
  /// a bounded height it cannot get inside another scroll view. Pass the bare
  /// content: only its vertical spacing is yours to set.
  final Widget? header;
  final Widget? footer;

  /// Rendered above [header], edge to edge instead of on the document column:
  /// a page-wide cover image spans the width, and scrolls away with the rest
  /// rather than staying pinned over the text.
  final Widget? cover;

  /// A handle on the page's editor, for a caller that has to move its
  /// scrolling — a thread following a message it just posted to the foot of the
  /// page (see [RichTextEditorState.revealFooter]).
  final GlobalKey<RichTextEditorState>? editorKey;

  final DocumentLayout layout;
  final RichTextFeatures? features;

  /// Glyphs swapped on the upstream "/" menu, keyed by the English label the
  /// editor ships. An argument for the reason every menu glyph is one: that
  /// menu is built in an overlay the editor creates itself.
  final Map<String, IconData> menuIcons;

  /// Read-only drops the gutter along with everything the editor drops.
  final bool editable;

  /// What a blank document reads as while nothing is focused. Null leaves it
  /// blank.
  final String? emptyPlaceholder;

  /// What the empty paragraph holding the cursor reads as.
  final String? hintPlaceholder;

  const DocumentEditor({
    required this.editorState,
    super.key,
    this.header,
    this.footer,
    this.cover,
    this.editorKey,
    this.layout = DocumentLayout.standard,
    this.features,
    this.menuIcons = const {},
    this.editable = true,
    this.emptyPlaceholder,
    this.hintPlaceholder,
  });

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  // The editor's gesture area covers its whole scroll view - header, footer and
  // side margins included - and its node hit-test resolves ANY offset to the
  // closest block, restoring a selection there and stealing the focus back,
  // e.g. when clicking away from the discussion's reply field. Only a gesture
  // landing on the rendered blocks may reach the selection service. A click
  // with 1px of mouse travel arrives as a pan, not a tap, so guarding taps
  // alone is not enough: canPanStart must be rejected too (a rejected pan start
  // never sets the drag anchor, which kills the whole pan sequence). Pan
  // updates stay unguarded so a text-selection drag that started on a block can
  // still travel past the edges.
  late final _outsideContentGuard = SelectionGestureInterceptor(
    key: 'document-editor-outside-content-guard',
    canTap: (details) => !_isOutsideContent(details.globalPosition),
    canDoubleTap: (details) => !_isOutsideContent(details.globalPosition),
    canTripleTap: (details) => !_isOutsideContent(details.globalPosition),
    canPanStart: (details) => !_isOutsideContent(details.globalPosition),
  );

  bool _isOutsideContent(Offset globalPosition) {
    // Never include the root: it is the page block, whose render box spans the
    // whole scroll view and would make the content rect cover everything.
    Rect? rect;
    for (final child in widget.editorState.document.root.children) {
      final childRect = _contentRect(child);
      if (childRect == null) continue;
      rect = rect == null ? childRect : rect.expandToInclude(childRect);
    }
    return rect != null && !rect.contains(globalPosition);
  }

  Rect? _contentRect(Node node) {
    Rect? rect;
    final box = node.renderBox;
    if (box != null) {
      rect = box.localToGlobal(Offset.zero) & box.size;
    }
    for (final child in node.children) {
      final childRect = _contentRect(child);
      if (childRect == null) continue;
      rect = rect == null ? childRect : rect.expandToInclude(childRect);
    }
    return rect;
  }

  @override
  void initState() {
    super.initState();

    if (!widget.editable) {
      return;
    }

    // The selection service only exists once AppFlowyEditor has mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.editorState.service.selectionService.registerGestureInterceptor(
          _outsideContentGuard,
        );
      }
    });
  }

  @override
  void dispose() {
    if (widget.editable &&
        widget.editorState.service.selectionServiceKey.currentState != null) {
      widget.editorState.service.selectionService.unregisterGestureInterceptor(
        _outsideContentGuard.key,
      );
    }
    super.dispose();
  }

  /// The package centres and pads each block on the document column but hands
  /// the header and the footer to its scroll list raw — put them back on that
  /// column, so no caller has to know its metrics.
  Widget? _onDocumentColumn(Widget? child) {
    if (child == null) {
      return null;
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.layout.maxWidth),
        child: Padding(padding: widget.layout.sidePadding(), child: child),
      ),
    );
  }

  /// The cover above the header, the cover alone, the header alone, or nothing
  /// — the editor's own header slot takes one widget.
  Widget? _headerWithCover() {
    final header = _onDocumentColumn(widget.header);
    final cover = widget.cover;

    if (cover == null) {
      return header;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [cover, ?header],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RichTextEditor(
      key: widget.editorKey,
      editorState: widget.editorState,
      features: widget.features ?? defaultRichTextFeatures,
      editable: widget.editable,
      scrollable: true,
      maxWidth: widget.layout.maxWidth,
      padding: widget.layout.editorPadding,
      blockActions: widget.editable
          ? (blockContext, builder) => DocumentGutter(
              blockComponentContext: blockContext,
              builder: builder,
              gutterWidth: widget.layout.gutterWidth,
            )
          : null,
      header: _headerWithCover(),
      footer: _onDocumentColumn(widget.footer),
      emptyPlaceholder: widget.emptyPlaceholder,
      hintPlaceholder: widget.hintPlaceholder,
    );
  }
}
