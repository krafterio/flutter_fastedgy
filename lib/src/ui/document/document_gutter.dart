/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../rich_text/rich_text_theme.dart';

/// The hover gutter of a block: "+" to insert a paragraph below, and the grip
/// to drag the block elsewhere in the document.
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

  Future<void> _insertParagraphBelow() async {
    final path = widget.blockComponentContext.node.path;
    final transaction = _editorState.transaction
      ..insertNode(path.next, paragraphNode());
    await _editorState.apply(transaction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorState.selection = Selection.collapsed(Position(path: path.next));
    });
  }

  Future<void> _moveNode(Offset dragOffset) async {
    final data = _editorState.selectionService.getDropTargetRenderData(
      dragOffset,
    );
    final targetPath = data?.cursorNode?.path;
    if (targetPath == null) return;
    final targetNode = _editorState.getNodeAtPath(targetPath);
    if (targetNode == null) return;

    final renderBox =
        targetNode.selectable?.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final blockRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final dropBelow = dragOffset.dy >= blockRect.top + blockRect.height / 2;

    final node = widget.blockComponentContext.node;
    final newPath = dropBelow ? targetPath.next : targetPath;
    if (node.path.equals(newPath) || node.path.isAncestorOf(newPath)) return;

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

  @override
  Widget build(BuildContext context) {
    // Total width must stay equal to the layout's gutter so the editor's
    // reduced left padding keeps block text aligned with the header.
    return SizedBox(
      width: widget.gutterWidth,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, right: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GutterButton(
              icon: FastEdgyIcons.of(context)[FastEdgyGlyph.add],
              onTap: _insertParagraphBelow,
            ),
            Draggable<Node>(
              data: _node,
              feedback: Opacity(
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
              ),
              onDragStarted: () =>
                  _editorState.selectionService.removeDropTarget(),
              onDragUpdate: (details) {
                _globalPosition = details.globalPosition;
                _editorState.selectionService.renderDropTargetForOffset(
                  details.globalPosition,
                  builder: _buildDropIndicator,
                );
                _editorState.scrollService?.startAutoScroll(
                  details.globalPosition,
                );
              },
              onDragEnd: (details) {
                _editorState.selectionService.removeDropTarget();
                final position = _globalPosition;
                if (position != null) {
                  _moveNode(position);
                }
              },
              child: _GutterButton(
                icon: FastEdgyIcons.of(context)[FastEdgyGlyph.gripRow],
                cursor: SystemMouseCursors.grab,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small enough to hang in a margin, wide enough to aim at.
const _buttonSize = 20.0;
const _iconSize = 14.0;

class _GutterButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  const _GutterButton({
    required this.icon,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
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
          width: _buttonSize,
          height: _buttonSize,
          decoration: BoxDecoration(
            color: _hovering ? theme.subtleSurface : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: _iconSize, color: theme.mutedText),
        ),
      ),
    );
  }
}
