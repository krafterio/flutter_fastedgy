/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../../../icons.dart';
import '../../rich_text_theme.dart';

/// A table drawn from the theme: its rules on the palette every border uses,
/// and the button that adds a row or a column carrying the glyph the rest of
/// the page adds with.
///
/// The width stays the editor's two: the border is what a column is resized by,
/// so a hairline would be a hairline to aim at.
///
/// Built from a theme rather than read from a context: the editor takes the
/// style as a final field on its builder, so it is fixed when the feature is
/// declared. An application that mounts its own theme passes the matching style
/// to [TableFeature]; what ships is derived from the floor.
TableStyle richTextTableStyle(
  RichTextTheme theme, [
  FastEdgyIcons icons = FastEdgyIcons.material,
]) {
  return TableStyle(
    borderColor: theme.border,
    borderHoverColor: theme.strongBorder,
    addIcon: Padding(
      padding: const EdgeInsets.all(3),
      child: Icon(icons[FastEdgyGlyph.add], size: 14, color: theme.mutedText),
    ),
  );
}

/// What the package insets its table by, inside the block itself.
///
/// It scrolls its columns sideways and pads that scroll view — ten pixels on
/// the left, written into the widget and reachable by nothing — so the table
/// stood ten pixels right of every paragraph on the page. Taken back here, its
/// left border lands on the margin the text is written against.
const _inset = 10.0;

/// The package's table, standing where every other block stands.
class AlignedTableComponentBuilder extends TableBlockComponentBuilder {
  AlignedTableComponentBuilder({
    super.configuration,
    super.tableStyle,
    super.menuBuilder,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final built = super.build(blockComponentContext);

    return _AlignedTable(
      node: built.node,
      configuration: built.configuration,
      showActions: built.showActions,
      actionBuilder: built.actionBuilder,
      actionTrailingBuilder: built.actionTrailingBuilder,
      table: built,
    );
  }
}

/// Moved rather than repadded: the inset lives inside the package's own widget,
/// and a block component has to stay the widget the editor built — it is what
/// carries the node's key, and so what a selection is measured from.
class _AlignedTable extends BlockComponentStatelessWidget {
  final Widget table;

  const _AlignedTable({
    required super.node,
    required super.configuration,
    required this.table,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
  });

  @override
  Widget build(BuildContext context) =>
      Transform.translate(offset: const Offset(-_inset, 0), child: table);
}
