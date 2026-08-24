/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:provider/provider.dart';

import '../icons.dart';
import '../interaction.dart';
import '../rich_text/rich_text_controls.dart';
import '../rich_text/rich_text_focus.dart';
import '../rich_text/rich_text_theme.dart';

/// The gutter of a block: "+" to insert a paragraph below, and the grip to drag
/// the block elsewhere in the document.
///
/// Two shapes, because the two ways of aiming at it have nothing in common.
///
/// A pointer hovers a block and the gutter appears beside it, both buttons
/// standing in the margin, the grip dragging the moment it is pulled.
///
/// A finger cannot hover, so the gutter shows on the block being written in and
/// nowhere else. It is one handle rather than two buttons: the margin is a
/// margin — widening it to fit thumb-sized targets would take the room from the
/// text on the very screens that have least of it. Holding the handle moves the
/// block, tapping it opens the block's menu, which is where everything that is
/// not a drag belongs.
class DocumentGutter extends StatefulWidget {
  final BlockComponentContext blockComponentContext;
  final BlockComponentBuilder builder;
  final double gutterWidth;

  const DocumentGutter({
    required this.blockComponentContext,
    required this.builder,
    required this.gutterWidth,
    super.key,
  });

  @override
  State<DocumentGutter> createState() => _DocumentGutterState();
}

class _DocumentGutterState extends State<DocumentGutter> {
  late final Node _node;
  late final BlockComponentContext _feedbackContext;
  late final EditorState _editorState = context.read<EditorState>();

  Offset? _globalPosition;

  /// Held for as long as the block is travelling: what shows the handle is the
  /// caret being in the block, and dropping it elsewhere moves the caret — the
  /// handle would take itself away mid-drag, and the drag with it.
  bool _dragging = false;

  /// Where the block would land, and the entry drawing it.
  final _line = ValueNotifier<Rect?>(null);
  OverlayEntry? _indicator;

  @override
  void initState() {
    super.initState();
    // Copy the node so the drag feedback doesn't follow live document edits.
    _node = widget.blockComponentContext.node.copyWith();
    _feedbackContext = BlockComponentContext(
      widget.blockComponentContext.buildContext,
      _node,
    );
  }

  @override
  void dispose() {
    _hideLine();
    _line.dispose();
    super.dispose();
  }

  Future<void> _insertParagraphBelow() async {
    final path = widget.blockComponentContext.node.path;
    final transaction = _editorState.transaction
      ..insertNode(path.next, paragraphNode());
    await _editorState.apply(transaction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorState.selection = Selection.collapsed(Position(path: path.next));
    });
  }

  /// Where the block would land if it were dropped here, and on which side of
  /// the block it is over.
  ///
  /// Asked of the document rather than of the editor's selection service: that
  /// service answers nothing at all on a touch platform — its whole drop-target
  /// half is a set of empty methods there, `getDropTargetRenderData` returning
  /// null — so a block dragged with a finger had nowhere to go and simply
  /// stayed where it was.
  ({Node node, Rect rect, bool below})? _dropTarget(Offset dragOffset) {
    ({Node node, Rect rect})? target;

    void visit(Node node) {
      final box = node.renderBox;

      if (box != null && box.attached) {
        final rect = box.localToGlobal(Offset.zero) & box.size;

        // The deepest block the pointer is inside, so a list item is offered
        // rather than the list holding it.
        if (dragOffset.dy >= rect.top && dragOffset.dy < rect.bottom) {
          target = (node: node, rect: rect);
        }
      }

      node.children.forEach(visit);
    }

    _editorState.document.root.children.forEach(visit);

    final found = target;

    if (found == null) {
      return null;
    }

    return (
      node: found.node,
      rect: found.rect,
      below: dragOffset.dy >= found.rect.top + found.rect.height / 2,
    );
  }

  Future<void> _moveNode(Offset dragOffset) async {
    final target = _dropTarget(dragOffset);

    if (target == null) {
      return;
    }

    final node = widget.blockComponentContext.node;
    final targetPath = target.node.path;
    final newPath = target.below ? targetPath.next : targetPath;

    if (node.path.equals(newPath) || node.path.isAncestorOf(newPath)) {
      return;
    }

    final transaction = _editorState.transaction..moveNode(newPath, node);
    await _editorState.apply(transaction);
  }

  Widget _buildDropIndicator(BuildContext context, DragAreaBuilderData data) {
    final targetNode = data.targetNode;
    final node = widget.blockComponentContext.node;
    if (node.path.equals(targetNode.path) ||
        node.path.isAncestorOf(targetNode.path)) {
      return const SizedBox.shrink();
    }
    final renderBox =
        targetNode.selectable?.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();
    final blockRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final dropBelow =
        data.dragOffset.dy >= blockRect.top + blockRect.height / 2;

    return Positioned(
      top: dropBelow ? blockRect.bottom : blockRect.top,
      left: blockRect.left,
      child: Container(
        width: blockRect.width,
        height: 2,
        color: RichTextTheme.of(context).dropIndicator,
      ),
    );
  }

  /// The block the finger is meant to be acting on: the one being written in.
  ///
  /// Every block builds its gutter on a touch platform — the editor's own hover
  /// gate is off there, or nothing would ever show — so this is what decides
  /// which of them is actually drawn.
  bool _holdsCaret(Selection? selection) =>
      widget.blockComponentContext.node.path.inSelection(selection);

  /// The block travelling under the finger or the pointer, drawn faintly.
  Widget _feedback() => Opacity(
    opacity: 0.7,
    child: Material(
      color: Colors.transparent,
      child: IntrinsicWidth(
        child: IntrinsicHeight(
          child: Provider.value(
            value: _editorState,
            child: widget.builder.build(_feedbackContext),
          ),
        ),
      ),
    ),
  );

  void _onDragStarted() {
    setState(() => _dragging = true);
    _editorState.selectionService.removeDropTarget();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _globalPosition = details.globalPosition;

    if (hasHoverPointer) {
      _editorState.selectionService.renderDropTargetForOffset(
        details.globalPosition,
        builder: _buildDropIndicator,
      );
    } else {
      _showLine(details.globalPosition);
    }

    _editorState.scrollService?.startAutoScroll(details.globalPosition);
  }

  void _onDragEnd(DraggableDetails details) {
    _editorState.selectionService.removeDropTarget();
    _hideLine();

    if (mounted) {
      setState(() => _dragging = false);
    }

    final position = _globalPosition;

    if (position != null) {
      unawaited(_moveNode(position));
    }
  }

  /// The line the editor would have drawn, drawn here instead.
  ///
  /// Same reason as [_dropTarget]: on a touch platform the editor's
  /// `renderDropTargetForOffset` is an empty method, so a block dragged with a
  /// finger travelled without ever saying where it was going to land.
  void _showLine(Offset dragOffset) {
    final target = _dropTarget(dragOffset);
    final node = widget.blockComponentContext.node;

    if (target == null ||
        node.path.equals(target.node.path) ||
        node.path.isAncestorOf(target.node.path)) {
      _hideLine();

      return;
    }

    _line.value = Rect.fromLTWH(
      target.rect.left,
      target.below ? target.rect.bottom : target.rect.top,
      target.rect.width,
      2,
    );

    if (_indicator != null) {
      return;
    }

    final color = RichTextTheme.of(context).dropIndicator;

    _indicator = OverlayEntry(
      builder: (context) => ValueListenableBuilder<Rect?>(
        valueListenable: _line,
        builder: (context, rect, _) => rect == null
            ? const SizedBox.shrink()
            : Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(child: ColoredBox(color: color)),
              ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_indicator!);
  }

  void _hideLine() {
    _line.value = null;
    _indicator?.remove();
    _indicator = null;
  }

  /// Pulled straight away under a pointer, held first under a finger.
  ///
  /// A drag that started on contact would be the page scrolling half the time:
  /// on a touch screen the same gesture belongs to the list underneath, and
  /// only holding still says which of the two was meant.
  Widget _draggable(Widget child) {
    if (hasHoverPointer) {
      return Draggable<Node>(
        data: _node,
        feedback: _feedback(),
        onDragStarted: _onDragStarted,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
        child: child,
      );
    }

    return LongPressDraggable<Node>(
      data: _node,
      feedback: _feedback(),
      onDragStarted: _onDragStarted,
      onDragUpdate: _onDragUpdate,
      onDragEnd: _onDragEnd,
      child: child,
    );
  }

  /// Both buttons in the margin, which is what a pointer that hovers gets.
  Widget _forPointer(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _GutterButton(
        icon: FastEdgyIcons.of(context)[FastEdgyGlyph.add],
        onTap: _insertParagraphBelow,
      ),
      _draggable(
        _GutterButton(
          icon: FastEdgyIcons.of(context)[FastEdgyGlyph.gripRow],
          cursor: SystemMouseCursors.grab,
        ),
      ),
    ],
  );

  /// One handle: hold it to move the block, tap it for everything else.
  Widget _forTouch(BuildContext context) => ValueListenableBuilder<Selection?>(
    valueListenable: _editorState.selectionNotifier,
    builder: (context, selection, _) => !_dragging && !_holdsCaret(selection)
        ? const SizedBox.shrink()
        : RichTextControls.of(context).menu(
            context,
            RichTextMenuSpec(
              actions: [
                RichTextMenuAction(
                  label: t('Insert a paragraph below'),
                  icon: FastEdgyIcons.of(context)[FastEdgyGlyph.add],
                  onTap: _insertParagraphBelow,
                ),
              ],
              anchor: (context, isOpen, toggle) => RichTextHoldsCaret(
                editorState: _editorState,
                open: isOpen,
                child: _draggable(
                  _GutterButton(
                    icon: FastEdgyIcons.of(context)[FastEdgyGlyph.gripRow],
                    // As wide as the margin allows, and no taller than the two
                    // buttons a pointer gets: the gutter stands in a Row beside
                    // the block, which takes the height of its tallest child, so
                    // a taller handle pushes the blocks apart. Width is free,
                    // height is not — and this is where the room came from.
                    width: widget.gutterWidth - 2,
                    iconSize: _touchIconSize,
                    active: isOpen,
                    onTap: toggle,
                  ),
                ),
              ),
            ),
          ),
  );

  /// The first line of the block, as it was last laid out, and where in it the
  /// handles hang.
  ///
  /// Measured rather than guessed at a constant: the handles stand level with
  /// the line a block opens with, and that line is a different height in a
  /// paragraph, in a heading and in a rule. The block is laid out beside them,
  /// so a margin taller than the line it hangs from decides the block's own
  /// height and pushes it off centre — which is why the height is capped to
  /// what the handles need rather than left to the buttons.
  ({double top, double height})? _hang;

  void _measureLine() {
    final node = widget.blockComponentContext.node;
    final selectable = node.selectable;
    final margin = context.findRenderObject();

    if (!mounted || selectable == null || margin is! RenderBox) {
      return;
    }

    // Both sides read in the one frame every block shares: what a block puts
    // above its first line — the padding of a list item, the air a heading
    // holds — is then already in the answer, rather than something this has to
    // know about and add.
    final line = selectable.getCursorRectInPosition(Position(path: node.path));

    if (line == null || !margin.attached) {
      return;
    }

    final from = selectable.localToGlobal(line.topLeft).dy;
    final top =
        (from -
                margin.localToGlobal(Offset.zero).dy +
                (line.height - _buttonSize) / 2)
            .clamp(0.0, double.infinity);
    // No taller than what the handles take: the row is as tall as the block or
    // as this, whichever wins, and any slack here would centre them in it.
    final hang = (top: top, height: top + _buttonSize);

    if (hang != _hang) {
      setState(() => _hang = hang);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLine());

    // Total width must stay equal to the layout's gutter so the editor's
    // reduced left padding keeps block text aligned with the header.
    //
    // Total height is what a block's row grows to when the block itself is
    // shorter, so the two shapes claim exactly the same: whatever a finger
    // gets, it costs the page no more room than a pointer has always cost it.
    return SizedBox(
      width: widget.gutterWidth,
      height: _hang?.height,
      child: Padding(
        padding: EdgeInsets.only(top: _hang?.top ?? 6, right: 2),
        child: hasHoverPointer ? _forPointer(context) : _forTouch(context),
      ),
    );
  }
}

/// Small enough to hang in a margin, wide enough to aim at.
const _buttonSize = 20.0;
const _iconSize = 14.0;

/// What a thumb gets over a pointer: the whole margin across. The height is the
/// same, and has to be.
const _touchIconSize = _iconSize + 2;

class _GutterButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final MouseCursor cursor;
  final double width;
  final double iconSize;

  /// Lit while what it opened is up.
  final bool active;

  const _GutterButton({
    required this.icon,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
    this.width = _buttonSize,
    this.iconSize = _iconSize,
    this.active = false,
  });

  @override
  State<_GutterButton> createState() => _GutterButtonState();
}

class _GutterButtonState extends State<_GutterButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.translucent,
        child: Container(
          width: widget.width,
          height: _buttonSize,
          decoration: BoxDecoration(
            color: _hovering || widget.active
                ? theme.subtleSurface
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: theme.mutedText,
          ),
        ),
      ),
    );
  }
}
