/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import '../../rich_text_controls.dart';
import '../../../icons.dart';
import '../../rich_text_focus.dart';
import '../../rich_text_theme.dart';

/// The grip: the block gutter's glyph, on a chip padded by the width of the
/// rule it sits on — every measurement it has comes off the table's own line,
/// so it reads as part of the table rather than as something dropped on it.
///
/// It has to live inside the row it belongs to, so what it costs is whatever it
/// covers of that row's first characters: small, then.
const _glyph = 12.0;

double get _pad => TableDefaults.borderWidth;

double get _grip => tableGripSize;

/// The side of the grip, for whoever places one themselves.
double get tableGripSize => _glyph + 2 * _pad;

/// What the package holds its handle out by, and what has to be given back.
///
/// Outside the row is not somewhere a handle can live. Nothing answers the
/// pointer beyond the box it is drawn in — a hit test stops at its bounds — so
/// the half of the package's handle that hung in the margin was painted and
/// nothing more: reaching for it left the row, and the row leaving took the
/// handle with it, every single time. Given back whole, the grip stands just
/// inside the edge it belongs to, where a hand can actually land on it.
const _held = 12.0;

/// The handle a row or a column is taken by, and the menu it opens.
///
/// The package's own is an icon in a card, with a menu of six untranslated
/// entries wide enough to cover the table it acts on. This is the menu the rest
/// of the app opens, in the language the reader chose.
Widget tableActionHandle(
  Node node,
  EditorState editorState,
  int position,
  TableDirection direction,
  VoidCallback? onOpen,
  VoidCallback? onClose, {
  bool held = true,
}) => _TableHandle(
  node: node,
  editorState: editorState,
  position: position,
  direction: direction,
  onOpen: onOpen,
  onClose: onClose,
  held: held,
);

class _TableHandle extends StatefulWidget {
  final Node node;
  final EditorState editorState;
  final int position;
  final TableDirection direction;

  /// Told when the menu opens and closes, so the handle stands there while it
  /// is up: hidden, the handle takes the menu down with it, and the pointer
  /// leaves the row the moment it heads for what it just opened.
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// Whether the package held the handle out of the row and it has to be given
  /// back. False where we place the handle ourselves and it was never held out
  /// (see the touch handles in `table_component.dart`).
  final bool held;

  const _TableHandle({
    required this.node,
    required this.editorState,
    required this.position,
    required this.direction,
    this.onOpen,
    this.onClose,
    this.held = true,
  });

  @override
  State<_TableHandle> createState() => _TableHandleState();
}

class _TableHandleState extends State<_TableHandle> {
  bool _open = false;
  bool _hovering = false;

  bool get _isColumn => widget.direction == TableDirection.col;

  /// Reported after the frame it is read in — the handle above rebuilds on it,
  /// and only on a change, or the rebuild would ask for another.
  void _report(bool open) {
    if (_open == open) {
      return;
    }

    _open = open;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => open ? widget.onOpen?.call() : widget.onClose?.call(),
    );
  }

  void _act(
    void Function(
      Node node,
      int position,
      EditorState editorState,
      TableDirection direction,
    )
    action, [
    int? at,
  ]) => action(
    widget.node,
    at ?? widget.position,
    widget.editorState,
    widget.direction,
  );

  @override
  Widget build(BuildContext context) {
    final icons = FastEdgyIcons.of(context);

    return RichTextControls.of(context).menu(
      context,
      RichTextMenuSpec(
        actions: [
          RichTextMenuAction(
            icon:
                icons[_isColumn
                    ? FastEdgyGlyph.insertLeft
                    : FastEdgyGlyph.insertAbove],
            label: _isColumn
                ? t('Insert a column before')
                : t('Insert a row above'),
            onTap: () => _act(TableActions.add),
          ),
          RichTextMenuAction(
            icon:
                icons[_isColumn
                    ? FastEdgyGlyph.insertRight
                    : FastEdgyGlyph.insertBelow],
            label: _isColumn
                ? t('Insert a column after')
                : t('Insert a row below'),
            onTap: () => _act(TableActions.add, widget.position + 1),
          ),
          RichTextMenuAction(
            icon: icons[FastEdgyGlyph.duplicate],
            label: _isColumn
                ? t('Duplicate the column')
                : t('Duplicate the row'),
            onTap: () => _act(TableActions.duplicate),
          ),
          RichTextMenuAction(
            icon: icons[FastEdgyGlyph.clear],
            label: t('Clear the content'),
            separated: true,
            onTap: () => _act(TableActions.clear),
          ),
          RichTextMenuAction(
            icon: icons[FastEdgyGlyph.delete],
            label: _isColumn ? t('Delete the column') : t('Delete the row'),
            destructive: true,
            onTap: () => _act(TableActions.delete),
          ),
        ],
        anchor: _handle,
      ),
    );
  }

  /// The strip a row or a column is grabbed by. Drawn here because where it
  /// sits, how long it runs and which way it faces are the table's business;
  /// what it is made of comes from the theme.
  Widget _handle(BuildContext context, bool isOpen, VoidCallback toggle) {
    final theme = RichTextTheme.of(context);

    _report(isOpen);

    // Lit by the whole strip, not by the glyph: a mark the size of a glyph
    // is one nobody can aim at, and it has to answer wherever a hand lands.
    final lit = _hovering || isOpen;
    final grip = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // The colour of the rule it sits on, so it reads as a thickening of
        // that line rather than as something dropped on the table — and it
        // takes the colour the rules themselves take when aimed at. Over a
        // cell's own text, a glyph on nothing is a glyph nobody sees.
        color: lit ? theme.strongBorder : theme.border,
        // Placed by the package, the grip hangs off one side of the rule:
        // square where it meets the line, rounded where it comes away from it,
        // so it reads as a thickening of that line rather than as something
        // loose. Placed by us it straddles the rule instead, and something
        // centred on a line has no side to be square on.
        borderRadius: !widget.held
            ? BorderRadius.circular(_pad * 2)
            : _isColumn
            ? BorderRadius.vertical(bottom: Radius.circular(_pad * 2))
            : BorderRadius.horizontal(right: Radius.circular(_pad * 2)),
      ),
      child: Icon(
        // Turned the way it is dragged, as the gutter's own is.
        FastEdgyIcons.of(context)[_isColumn
            ? FastEdgyGlyph.gripColumn
            : FastEdgyGlyph.gripRow],
        size: _glyph,
        color: lit ? theme.ink : theme.mutedText,
      ),
    );

    return RichTextHoldsCaret(
      editorState: widget.editorState,
      open: isOpen,
      child: Padding(
        // Everything the package holds it out by, given back — less the rule
        // itself for a row, whose cell begins on the far side of it. Both
        // grips then start on the outer edge of the line they sit on, rather
        // than one of them a rule further in than the other.
        padding: !widget.held
            ? EdgeInsets.zero
            : _isColumn
            ? const EdgeInsets.only(top: _held)
            : EdgeInsets.only(left: _held - TableDefaults.borderWidth),
        child: SizedBox(
          // Thin across the edge, and no longer along it than the grip it
          // holds. The package wraps whatever we hand it in a mouse region of
          // its own, an opaque one: a strip running the whole width of a
          // column took the pointer from every cell under it, and a row whose
          // cell never saw the pointer never showed its own handle at all.
          width: _isColumn ? _grip + 2 * _pad : _grip,
          height: _isColumn ? _grip : double.infinity,
          child: Align(
            alignment: _isColumn ? Alignment.topCenter : Alignment.centerLeft,
            child: LayoutBuilder(
              builder: (context, box) {
                // Never longer than what it marks: a short row or a narrow
                // column takes what it has, less the rule on either side.
                final along =
                    ((_isColumn ? box.maxWidth : box.maxHeight) - 2 * _pad)
                        .clamp(_glyph, _grip);

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  // Lets the row around it see the pointer too: it is that row
                  // being hovered which puts the handle there, and absorbing
                  // the pointer here would read as having left it.
                  opaque: false,
                  onEnter: (_) => setState(() => _hovering = true),
                  onExit: (_) => setState(() => _hovering = false),
                  child: GestureDetector(
                    // Where the package reveals it, only what is drawn answers:
                    // taking the whole strip took the pointer from the cell
                    // underneath, and a row whose cell never saw the pointer
                    // never showed its handle at all.
                    //
                    // Placed by us there is nothing to reveal and nothing to let
                    // through, and deferring to the child leaves the glyph as
                    // the only thing anyone can hit — a chip whose left-most
                    // pixels answer and whose middle does not.
                    behavior: widget.held
                        ? HitTestBehavior.deferToChild
                        : HitTestBehavior.opaque,
                    onTap: toggle,
                    child: SizedBox(
                      width: _isColumn ? along : _grip,
                      height: _isColumn ? _grip : along,
                      child: grip,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
