/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:provider/provider.dart';

import 'link_menu.dart';

/// How long a single click waits before opening the card, so a double click
/// can cancel it and open the link instead. The package's own delay.
const _doubleClickWindow = Duration(milliseconds: 200);

/// Clicking a rendered link opens our card, not the package's.
///
/// A link reaches the document by more routes than the toolbar — a pasted URL
/// is autolinked when the markdown is read back — so the click has to be ours
/// too, or half the links in a document answer to the package's English menu.
///
/// Modelled on `defaultTextSpanDecoratorForAttribute`: ctrl/cmd-click and
/// double click still open the link itself.
TextSpan linkTextSpanDecorator(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final href = text.attributes?[AppFlowyRichTextKeys.href] as String?;

  if (href == null) {
    return before;
  }

  final editorState = context.read<EditorState>();

  Timer? timer;
  int taps = 0;

  final recognizer = TapGestureRecognizer()
    ..onTap = () {
      taps += 1;
      timer?.cancel();

      final keyboard = HardwareKeyboard.instance;

      if (taps == 2 ||
          !editorState.editable ||
          keyboard.isControlPressed ||
          keyboard.isMetaPressed) {
        taps = 0;
        unawaited(openLink(href));

        return;
      }

      timer = Timer(_doubleClickWindow, () {
        taps = 0;
        final selection = Selection.single(
          path: node.path,
          startOffset: index,
          endOffset: index + text.text.length,
        );
        editorState.updateSelectionWithReason(
          selection,
          reason: SelectionUpdateReason.uiEvent,
        );
        // The selection has to be laid out before the card can be placed under it.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => showLinkEditor(context, editorState, selection),
        );
      });
    };

  return TextSpan(
    style: before.style,
    text: text.text,
    recognizer: recognizer,
    mouseCursor: SystemMouseCursors.click,
  );
}

/// Cmd/Ctrl + K. Listed before the package's own, which the editor stops at as
/// soon as this one reports the key handled.
final linkShortcut = CommandShortcutEvent(
  key: 'link menu',
  getDescription: () => t('Link'),
  command: 'ctrl+k',
  macOSCommand: 'cmd+k',
  handler: (editorState) {
    final selection = editorState.selection;

    if (selection == null || selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final context = editorState
        .getNodeAtPath(selection.end.path)
        ?.key
        .currentContext;

    if (context == null) {
      return KeyEventResult.ignored;
    }

    showLinkEditor(context, editorState, selection);

    return KeyEventResult.handled;
  },
);
