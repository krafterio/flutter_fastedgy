/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../icons.dart';
import '../../../interaction.dart';
import '../../rich_text_theme.dart';
import 'table_handle.dart';

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

/// The side of the button that adds a row or a column, and the strip the
/// package leaves for it on the far side of the table.
const _add = 24.0;
const _addStrip = 28.0;

/// What a finger is given to take a column edge by.
///
/// The package's own is the border itself — two pixels, with a drag recognizer
/// on it: aimable with a mouse, and nothing a thumb will ever land on.
const _grab = 28.0;

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
  Widget build(BuildContext context) {
    final aligned = Transform.translate(
      offset: const Offset(-_inset, 0),
      child: table,
    );

    return hasHoverPointer
        ? aligned
        : _TouchHandles(table: node, child: aligned);
  }
}

/// The row and column handles of the cell being written in, placed by us.
///
/// The package hangs its own off a hover: they live inside a `Visibility` whose
/// condition is a `MouseRegion` on the row and another on the column, and an
/// invisible one does not even build its child — so under a thumb the handles
/// were not hidden, they were never made. Nothing it offers can turn that off.
///
/// What is drawn is the same handle as ever ([tableActionHandle]); only the
/// moment and the place are ours. Two of them rather than one per row and one
/// per column: what a finger is working on is one cell, and a table covered in
/// grips has none you can aim at.
class _TouchHandles extends StatefulWidget {
  final Node table;
  final Widget child;

  const _TouchHandles({required this.table, required this.child});

  @override
  State<_TouchHandles> createState() => _TouchHandlesState();
}

class _TouchHandlesState extends State<_TouchHandles> {
  /// The box every position is measured against — ours, so the handles follow
  /// the table wherever the page puts it.
  final _box = GlobalKey();

  late final EditorState _editorState = context.read<EditorState>();

  /// The cell the caret is in, or null when it is somewhere else entirely.
  Node? _cellOf(Selection? selection) {
    final path = selection?.start.path;
    final table = widget.table.path;

    if (path == null || path.length <= table.length) {
      return null;
    }

    for (var i = 0; i < table.length; i++) {
      if (path[i] != table[i]) {
        return null;
      }
    }

    final index = path[table.length];

    return index < widget.table.children.length
        ? widget.table.children[index]
        : null;
  }

  /// Where a cell stands inside this block.
  Rect? _rectOf(Node cell) {
    final box = cell.renderBox;
    final self = _box.currentContext?.findRenderObject();

    if (box == null || !box.attached || self is! RenderBox || !self.attached) {
      return null;
    }

    return self.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  /// Set while the column edge is held, so the table follows the finger
  /// without a transaction per frame — the same bargain the package makes.
  int? _resizing;
  double? _width;

  void _startResize(int column) {
    final table = TableNode(node: widget.table);

    setState(() {
      _resizing = column;
      _width = table.getColWidth(column);
    });
  }

  void _resize(int column, double deltaX) {
    final table = TableNode(node: widget.table);
    final width = (_width ?? table.getColWidth(column)) + deltaX;

    setState(() => _width = width);
    table.setColWidth(column, width);
  }

  /// Written down once the finger is let go, and forced: the width the table
  /// has been carrying frame by frame is already the one we want, so nothing
  /// would be recorded without it.
  void _endResize(int column) {
    final table = TableNode(node: widget.table);
    final transaction = _editorState.transaction;

    table.setColWidth(
      column,
      table.getColWidth(column),
      transaction: transaction,
      force: true,
    );
    transaction.afterSelection = transaction.beforeSelection;

    unawaited(_editorState.apply(transaction));

    setState(() {
      _resizing = null;
      _width = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt as the caret moves, and again whenever the table scrolls its
    // columns sideways under it — the handles are placed from where the cells
    // are, and a cell that slid is a handle pointing at the wrong column.
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        setState(() {});

        return false;
      },
      child: ValueListenableBuilder<Selection?>(
        valueListenable: _editorState.selectionNotifier,
        builder: (context, selection, child) {
          final cell = _cellOf(selection);
          final rect = cell == null ? null : _rectOf(cell);

          return Stack(
            key: _box,
            children: [
              child!,
              if (cell != null && rect != null) ..._handles(cell, rect),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }

  /// Everything drawn over the table, placed from where its cells actually
  /// are — never from the edges of the block, which reach past the table on
  /// every side: the block has its own padding above and the table is narrower
  /// than the column it stands in. Measured from the block, the row grip hung
  /// in the page's margin and the column grip floated above the top rule.
  List<Widget> _handles(Node cell, Rect rect) {
    final table = TableNode(node: widget.table);
    final column = cell.attributes[TableCellBlockKeys.colPosition] as int?;
    final row = cell.attributes[TableCellBlockKeys.rowPosition] as int?;
    final head = _rectOf(table.getCell(0, 0));

    if (head == null) {
      return const [];
    }

    final foot = _rectOf(table.getCell(0, table.rowsLen - 1)) ?? head;

    return [
      if (column != null)
        for (final top in [_rectOf(table.getCell(column, 0))])
          if (top != null)
            Positioned(
              // Along the column and straddling the table's top rule. Never
              // past the block's own edge: nothing answers a touch beyond the
              // box it is drawn in, and a grip half outside is half dead.
              left: top.left,
              width: top.width,
              top: max(0, top.top - tableGripSize / 2),
              child: _handle(column, TableDirection.col),
            ),
      if (row != null)
        Positioned(
          // Straddling the table's left rule, not the block's left edge.
          left: max(0, head.left - tableGripSize / 2),
          top: rect.top,
          height: rect.height,
          child: _handle(row, TableDirection.row),
        ),
      ..._edges(table, head.top, foot.bottom - head.top),
      ..._adders(table, head, foot),
    ];
  }

  /// The two buttons that add a row and a column.
  ///
  /// The package draws them in the strip it already leaves on the far side of
  /// the table, and hides them behind a hover of their own — so on a touch
  /// screen the strip is there, taking its width, and nothing ever appears in
  /// it. These stand in that same strip.
  List<Widget> _adders(TableNode table, Rect head, Rect foot) {
    final last = _rectOf(table.getCell(table.colsLen - 1, 0));

    if (last == null) {
      return const [];
    }

    return [
      Positioned(
        left: last.right,
        width: _addStrip,
        top: head.top,
        height: foot.bottom - head.top,
        child: _AddButton(
          onTap: () => TableActions.add(
            widget.table,
            table.colsLen,
            _editorState,
            TableDirection.col,
          ),
        ),
      ),
      Positioned(
        left: head.left,
        width: last.right - head.left,
        top: foot.bottom,
        height: _addStrip,
        child: _AddButton(
          onTap: () => TableActions.add(
            widget.table,
            table.rowsLen,
            _editorState,
            TableDirection.row,
          ),
        ),
      ),
    ];
  }

  /// A strip astride every column's right-hand rule, running the height of the
  /// table.
  ///
  /// Every column and not only the one being written in: the strip is wide
  /// enough to be aimed at, so it covers the first pixels of the cell beyond
  /// it — and a strip that belonged to the caret's column moved to another
  /// edge the moment that touch put the caret in the next cell. What was
  /// grabbed then was never what was widened.
  List<Widget> _edges(TableNode table, double top, double height) {
    final edges = <Widget>[];

    for (var column = 0; column < table.colsLen; column++) {
      final rect = _rectOf(table.getCell(column, 0));

      if (rect == null) {
        continue;
      }

      edges.add(
        Positioned(
          left: rect.right - _grab / 2,
          width: _grab,
          top: top,
          height: height,
          child: _ColumnEdge(
            lit: _resizing == column,
            onStart: () => _startResize(column),
            onMove: (deltaX) => _resize(column, deltaX),
            onEnd: () => _endResize(column),
          ),
        ),
      );
    }

    return edges;
  }

  /// Both directions act on the table itself, which is what the package hands
  /// its own handles too — a row is not the cell it was reached from.
  Widget _handle(int position, TableDirection direction) => tableActionHandle(
    widget.table,
    _editorState,
    position,
    direction,
    null,
    null,
    // Never held out of the row here: we are placing it inside the block, so
    // there is nothing to give back.
    held: false,
  );
}

/// The strip a column is widened by, wide enough to be aimed at with a thumb.
///
/// Moved from the raw pointer, for the reason everything else here is: the
/// table sits in a page that scrolls and over an editor that answers the first
/// contact by moving the selection, so a drag recognizer has an arena to win
/// before the column moves at all — and under a thumb it loses it.
class _ColumnEdge extends StatelessWidget {
  final bool lit;
  final VoidCallback onStart;
  final void Function(double deltaX) onMove;
  final VoidCallback onEnd;

  const _ColumnEdge({
    required this.lit,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return Listener(
      onPointerDown: (_) => onStart(),
      onPointerMove: (event) => onMove(event.delta.dx),
      onPointerUp: (_) => onEnd(),
      onPointerCancel: (_) => onEnd(),
      child: GestureDetector(
        // The press is handled above; this only keeps the tap off the text
        // under the strip.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Center(
          // Nothing of its own to look at until it is held: the rule it stands
          // on is already drawn, and a second line beside it reads as a fault
          // in the table.
          child: SizedBox(
            width: TableDefaults.borderWidth * 2,
            child: ColoredBox(
              color: lit ? theme.strongBorder : const Color(0x00000000),
            ),
          ),
        ),
      ),
    );
  }
}

/// The button that adds a row or a column: the glyph and nothing else.
///
/// No chip under it, unlike the grips: those stand on a rule and have to read
/// as a thickening of it, while this one stands in open margin where a filled
/// square is just a smudge.
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return Center(
      child: GestureDetector(
        // Everything it covers answers, not just the glyph: a chip whose
        // drawing is the only thing anyone can hit reads as broken.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          // Bigger than the glyph on purpose: what answers a thumb is the box,
          // what it aims at is the mark inside it.
          width: _add,
          height: _add,
          child: Icon(
            FastEdgyIcons.of(context)[FastEdgyGlyph.add],
            size: 14,
            color: theme.mutedText,
          ),
        ),
      ),
    );
  }
}
