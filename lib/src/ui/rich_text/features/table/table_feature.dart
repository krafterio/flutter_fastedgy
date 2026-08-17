/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../../rich_text_action.dart';
import '../../rich_text_feature.dart';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import '../../../icons.dart';
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

  /// Beside the blocks a button already makes: a table is reached about as
  /// often as a picture, and the "/" menu costs a character typed and a list
  /// read on a phone.
  @override
  List<RichTextAction> get actions => [
    RichTextAction(
      id: 'table',
      glyph: FastEdgyGlyph.table,
      getLabel: () => t('Table'),
      group: 3,
      isActive: (_) => false,
      // Only on a line of its own: a table is not something a paragraph turns
      // into, it is something written between two of them.
      isEnabled: (editorState) => editorState.selection?.isCollapsed ?? false,
      run: (editorState) async {
        final selection = editorState.selection;
        final node = selection == null
            ? null
            : editorState.getNodeAtPath(selection.end.path);

        if (selection == null || node == null || !selection.isCollapsed) {
          return;
        }

        final table = TableNode.fromList([
          ['', ''],
          ['', ''],
        ]);
        final transaction = editorState.transaction;
        // An empty line is where it goes, rather than something to keep above
        // it — which is what the "/" menu leaves behind on that line.
        final blank = node.delta?.isEmpty ?? false;
        final at = blank ? selection.end.path : selection.end.path.next;

        transaction.insertNode(at, table.node);

        if (blank) {
          transaction.deleteNode(node);
        }

        transaction.afterSelection = Selection.collapsed(
          Position(path: at + [0, 0]),
        );

        await editorState.apply(transaction);
      },
    ),
  ];

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
