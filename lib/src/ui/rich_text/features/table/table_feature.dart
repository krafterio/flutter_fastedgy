/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../../rich_text_feature.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import '../../rich_text_theme.dart';
import 'table_component.dart';
import 'table_handle.dart';
import 'table_markdown.dart';

/// A table: the package's, standing where the other blocks stand, and written
/// and read back by us.
///
/// What the package cannot do is survive markdown: a cell holding a line break
/// or a pipe wrote a row that was no longer one, and the table was gone on the
/// next read.
class TableFeature extends RichTextFeature {
  /// What its rules and its add button are drawn with. The editor fixes this at
  /// declaration, so it cannot follow a theme mounted later — an application
  /// that has one passes `richTextTableStyle(itsTheme, itsIcons)`.
  final TableStyle? style;

  const TableFeature({this.style});

  /// Both, because a table hangs its handles off two blocks: the columns' off
  /// the table, the rows' off each cell. Overriding one left the other opening
  /// the package's own menu.
  @override
  Map<String, BlockComponentBuilder> get builders => {
    TableBlockKeys.type: AlignedTableComponentBuilder(
      tableStyle: style ?? richTextTableStyle(RichTextTheme.fallback),
      menuBuilder: tableActionHandle,
    ),
    TableCellBlockKeys.type: TableCellBlockComponentBuilder(
      menuBuilder: tableActionHandle,
    ),
  };

  @override
  List<NodeParser> get markdownEncoders => const [WholeTableNodeParser()];

  @override
  List<CustomMarkdownParser> get markdownDecoders => const [
    WholeTableParser(),
    TableWidthsParser(),
  ];

  @override
  Document afterMarkdown(Document document) => tableWidths(document);
}
