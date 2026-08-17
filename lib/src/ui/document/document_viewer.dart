/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';

import '../rich_text/rich_text_feature.dart';
import '../rich_text/rich_text_features.dart';
import '../rich_text/rich_text_viewer.dart';
import 'document_layout.dart';

/// What a [DocumentEditor] writes, read.
///
/// A [RichTextViewer] put on the document's column, so a page displayed reads at
/// the width it was written at. Everything the editor adds for writing — the
/// gutter, the scrolling, the toolbar — is absent, and so is the editor itself:
/// this is the light path, fit to repeat.
///
/// It does not scroll. Give it to whatever scrolls the page around it.
class DocumentViewer extends StatelessWidget {
  final EditorState editorState;
  final RichTextFeatures? features;
  final DocumentLayout layout;

  /// Above and below the blocks, on their column.
  final Widget? header;
  final Widget? footer;

  const DocumentViewer({
    required this.editorState,
    super.key,
    this.features,
    this.layout = DocumentLayout.standard,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.maxWidth),
        child: Padding(
          // The column is applied once, here, rather than per block: the view
          // then fills what it is given.
          padding: layout.sidePadding(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?header,
              RichTextViewer(
                editorState: editorState,
                features: features ?? defaultRichTextFeatures,
              ),
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}
