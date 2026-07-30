/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show Timer;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
import 'package:flutter/material.dart';

import '../theme/component_theme.dart';
import 'rich_text_action.dart';
import 'rich_text_action_bar.dart';
import 'rich_text_popover.dart';
import 'rich_text_toolbar_theme.dart';

/// All the room four short labels may claim; the card takes the width of what
/// it actually holds and wraps rather than run past this.
const _menuWidth = 320.0;

/// The formatting strip, raised by a held press on a bare caret.
///
/// The same strip a selection raises, and deliberately: one row, one set of
/// actions, one place to look. What a held press adds is the case a selection
/// cannot reach — cut, copy and paste live on that strip, and pasting happens
/// with nothing selected far more often than into a selection.
///
/// Only on a bare caret, for the same reason: with words selected the strip is
/// already up, and raising a second one over it would be two of the same thing.
///
/// Held press then release, as the platform does it: the press itself belongs
/// to the editor, which puts the caret where the finger is and shows a
/// magnifier while it travels. The strip is what the release leaves behind.
class RichTextTouchMenu extends StatefulWidget {
  final EditorState editorState;

  /// The strip's own, handed over rather than built here: what it offers is
  /// decided in one place (see RichTextEditor).
  final List<RichTextAction> actions;

  final Widget child;

  const RichTextTouchMenu({
    required this.editorState,
    required this.actions,
    required this.child,
    super.key,
  });

  @override
  State<RichTextTouchMenu> createState() => _RichTextTouchMenuState();
}

class _RichTextTouchMenuState extends State<RichTextTouchMenu> {
  Timer? _held;
  Offset? _start;
  bool _armed = false;

  @override
  void dispose() {
    _held?.cancel();
    super.dispose();
  }

  void _forget() {
    _held?.cancel();
    _held = null;
    _start = null;
    _armed = false;
  }

  void _onDown(PointerDownEvent event) {
    _forget();
    _start = event.position;
    _held = Timer(kLongPressTimeout, () => _armed = true);
  }

  /// Only what happens before the press is a press: a finger that travels after
  /// that is dragging the caret, and the menu still belongs to its release.
  void _onMove(PointerMoveEvent event) {
    final start = _start;

    if (!_armed &&
        start != null &&
        (event.position - start).distance > kTouchSlop) {
      _forget();
    }
  }

  void _onUp(PointerEvent event) {
    final armed = _armed && event is PointerUpEvent;

    _forget();

    if (armed) {
      // After the frame: the press that ends here is what moved the selection,
      // and the menu hangs off where that selection was laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    }
  }

  void _show() {
    final selection = widget.editorState.selection;

    // With words selected the strip is already up on its own.
    if (!mounted || selection == null || !selection.isCollapsed) {
      return;
    }

    // Read here and handed over: the strip is built into an overlay, where a
    // theme scoped around the editor is nowhere to be found.
    final theme = RichTextToolbarTheme.of(context);

    showRichTextPopover(
      context,
      widget.editorState,
      selection,
      width: _menuWidth,
      fitsContent: true,
      padding: const EdgeInsets.all(4),
      builder: (context, dismiss) => ComponentTheme<RichTextToolbarTheme>(
        data: theme,
        child: RichTextActionBar(
          editorState: widget.editorState,
          actions: widget.actions,
          onRun: dismiss,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: widget.child,
  );
}
