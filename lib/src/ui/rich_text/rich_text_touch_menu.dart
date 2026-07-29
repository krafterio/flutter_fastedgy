/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show Timer, unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'rich_text_controls.dart';
import 'rich_text_feature.dart';
import 'rich_text_paste.dart';
import 'rich_text_popover.dart';
import 'rich_text_theme.dart';

/// All the room four short labels may claim; the card takes the width of what
/// it actually holds and wraps rather than run past this.
const _menuWidth = 320.0;

/// The menu a finger gets on a held press: cut, copy, paste, select all.
///
/// The editor underneath offers those on a right-click and nowhere else, and it
/// speaks to the keyboard itself rather than through the field the system draws
/// its own callout for — so on a touch screen there was no way to paste at all.
///
/// Held press then release, as the platform does it: the press itself belongs
/// to the editor, which puts the caret where the finger is and shows a
/// magnifier while it travels. The menu is what the release leaves behind.
class RichTextTouchMenu extends StatefulWidget {
  final EditorState editorState;

  /// What the document can hold, so pasted markdown comes back as the blocks
  /// this editor knows how to write.
  final RichTextFeatures features;

  final Widget child;

  const RichTextTouchMenu({
    required this.editorState,
    required this.features,
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

    if (!mounted || selection == null) {
      return;
    }

    showRichTextPopover(
      context,
      widget.editorState,
      selection,
      width: _menuWidth,
      fitsContent: true,
      padding: const EdgeInsets.all(4),
      builder: (context, dismiss) => _Actions(
        editorState: widget.editorState,
        features: widget.features,
        onDone: dismiss,
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

class _Actions extends StatelessWidget {
  final EditorState editorState;
  final RichTextFeatures features;
  final VoidCallback onDone;

  const _Actions({
    required this.editorState,
    required this.features,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final selection = editorState.selection;
    final selected = selection != null && !selection.isCollapsed;

    return Wrap(
      children: [
        if (selected)
          _action(context, t('Cut'), () => cutCommand.handler(editorState)),
        if (selected)
          _action(context, t('Copy'), () => copyCommand.handler(editorState)),
        _action(
          context,
          t('Paste'),
          () => unawaited(pasteRichText(editorState, features: features)),
        ),
        _action(
          context,
          t('Select all'),
          () => selectAllCommand.handler(editorState),
        ),
      ],
    );
  }

  Widget _action(BuildContext context, String label, VoidCallback run) {
    final theme = RichTextTheme.of(context);

    return RichTextControls.of(context).tappable(
      context,
      RichTextTapSpec(
        onTap: () {
          run();
          onDone();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: TextStyle(color: theme.ink, fontSize: 14)),
        ),
      ),
    );
  }
}
