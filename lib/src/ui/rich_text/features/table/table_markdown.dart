/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// A line break inside a cell, written the one way a table can hold one.
///
/// A row is a line: a real newline cut the row in two, the halves read as
/// nothing in particular, and the whole table was lost on the next read.
const _lineBreak = '<br>';

/// What the package's encoder writes where a block holds nothing.
const _blankLine = '&nbsp;';

/// The widths a table's columns were dragged to, carried in a marker of its
/// own — markdown itself says nothing of how wide a column is drawn, so a
/// resized table came back at the default width on the next read.
///
/// A comment rather than anything visible: every reader but ours passes over
/// it, and the table above it reads as the plain markdown table it is.
final _widths = RegExp(r'^<!--\s*cols:\s*([\d.,\s]+?)\s*-->$');

/// The block a read marker becomes, until [tableWidths] folds it into the table
/// it belongs to. It is never rendered and never reaches an editor.
const tableWidthsType = 'table/widths';

const _widthsAttribute = 'widths';

/// Gives each table the widths written under it and drops the markers.
///
/// The pass a node parser cannot do: what a marker says belongs to the block
/// before it, and a parser only ever sees its own.
Document tableWidths(Document document) {
  final children = document.root.children;

  if (children.every((node) => node.type != tableWidthsType)) {
    return document;
  }

  final kept = <Node>[];

  for (final node in children) {
    if (node.type != tableWidthsType) {
      kept.add(node);

      continue;
    }

    final table = kept.isEmpty ? null : kept.last;

    if (table?.type == TableBlockKeys.type) {
      _widen(
        table!,
        (node.attributes[_widthsAttribute] as List?)
                ?.whereType<num>()
                .toList() ??
            const [],
      );
    }
  }

  return Document.blank()..insert([0], kept);
}

void _widen(Node table, List<num> widths) {
  for (final cell in table.children) {
    final column = cell.attributes[TableCellBlockKeys.colPosition];

    if (column is int && column < widths.length) {
      cell.updateAttributes({
        TableCellBlockKeys.width: widths[column].toDouble(),
      });
    }
  }
}

/// Writes a table one line per row, everything a cell holds kept on that line.
///
/// The package's own parser hands each cell to the encoder as it stands and
/// writes the result between two pipes. A cell holding a line break, or a pipe,
/// therefore wrote a row that was no longer a row — and a table markdown cannot
/// read back is a table gone, along with everything written in it.
class WholeTableNodeParser extends NodeParser {
  const WholeTableNodeParser();

  @override
  String get id => TableBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final columns = node.attributes[TableBlockKeys.colsLen];
    final rows = node.attributes[TableBlockKeys.rowsLen];

    if (columns is! int || rows is! int || columns <= 0 || rows <= 0) {
      return '';
    }

    final lines = <String>[];

    for (var row = 0; row < rows; row++) {
      lines.add(
        '|${[for (var column = 0; column < columns; column++) _cell(node, column, row, encoder)].join('|')}|',
      );

      // Without the line under its first row a table is not a table at all:
      // every reader takes the whole of it for a paragraph.
      if (row == 0) {
        lines.add('|${List.filled(columns, '-').join('|')}|');
      }
    }

    return '${lines.join('\n')}${_marker(node, columns)}';
  }

  /// The widths line, written only where a column was actually dragged: a table
  /// left as it came needs no marker, and its markdown stays the plain thing
  /// anything can read.
  String _marker(Node node, int columns) {
    final byDefault =
        (node.attributes[TableBlockKeys.colDefaultWidth] as num?)?.toDouble() ??
        TableDefaults.colWidth;
    final widths = [
      for (var column = 0; column < columns; column++)
        (_cellAt(node, column, 0)?.attributes[TableCellBlockKeys.width] as num?)
                ?.toDouble() ??
            byDefault,
    ];

    if (widths.every((width) => width == byDefault)) {
      return '';
    }

    return '\n<!-- cols:${widths.map((width) => width.round()).join(',')} -->';
  }

  /// What one cell reads as, on a single line.
  ///
  /// Written by the encoder it was handed, so what a cell holds is written the
  /// way it is written anywhere else — a mention in a cell included.
  String _cell(
    Node table,
    int column,
    int row,
    DocumentMarkdownEncoder? encoder,
  ) {
    final cell = _cellAt(table, column, row);

    if (cell == null || encoder == null) {
      return '';
    }

    final markdown = encoder.convert(Document(root: cell)).trim();

    // What the encoder writes for a line with nothing on it, so that the line
    // survives at all. A cell needs no such thing — it is held open by the
    // pipes around it — and reading it back gave every empty cell a space.
    if (markdown == _blankLine) {
      return '';
    }

    return markdown.replaceAll('|', r'\|').replaceAll('\n', _lineBreak);
  }
}

/// Reads a table back with the line breaks its cells were written with.
///
/// Ahead of the package's own parser, which it does the structural work
/// through: what it cannot know is that a `<br>` in a cell is a line break we
/// wrote, and not the four characters somebody typed.
class WholeTableParser extends CustomMarkdownParser {
  const WholeTableParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    final nodes = const MarkdownTableListParserV2().transform(
      element,
      parsers,
      listType: listType,
      startNumber: startNumber,
    );

    for (final node in nodes) {
      _unbreak(node);
    }

    return nodes;
  }

  void _unbreak(Node node) {
    final delta = node.delta;

    if (delta != null) {
      node.updateAttributes({blockComponentDelta: _unbroken(delta).toJson()});
    }

    for (final child in node.children) {
      _unbreak(child);
    }
  }

  Delta _unbroken(Delta delta) => Delta(
    operations: [
      for (final operation in delta)
        if (operation is TextInsert && operation.text.contains(_lineBreak))
          TextInsert(
            operation.text.replaceAll(_lineBreak, '\n'),
            attributes: operation.attributes,
          )
        else
          operation,
    ],
  );
}

/// Reads the widths marker back as a block of its own, for [tableWidths] to
/// fold into the table above it.
class TableWidthsParser extends CustomMarkdownParser {
  const TableWidthsParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    final match = _widths.firstMatch(element.textContent.trim());

    if (match == null) {
      return [];
    }

    final widths = [
      for (final width in match.group(1)!.split(','))
        ?double.tryParse(width.trim()),
    ];

    return widths.isEmpty
        ? []
        : [
            Node(type: tableWidthsType, attributes: {_widthsAttribute: widths}),
          ];
  }
}

/// The cell at [column] and [row], which a table holds as a flat list.
Node? _cellAt(Node table, int column, int row) {
  for (final cell in table.children) {
    if (cell.attributes[TableCellBlockKeys.colPosition] == column &&
        cell.attributes[TableCellBlockKeys.rowPosition] == row) {
      return cell;
    }
  }

  return null;
}
