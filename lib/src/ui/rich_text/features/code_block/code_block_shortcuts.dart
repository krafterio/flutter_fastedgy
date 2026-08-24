/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'code_block_component.dart';

/// Whether the caret sits inside a code block — what every shortcut of the
/// block asks before it does anything, and what tells the editor that Enter
/// belongs to the block rather than to whatever else is bound to it.
bool isInCodeBlock(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null) return false;
  return editorState.getNodeAtPath(selection.end.path)?.type ==
      CodeBlockKeys.type;
}

/// Wraps a character shortcut so it never fires inside a code block: the raw
/// character falls through to plain insertion instead. This is what turns
/// Enter into a literal newline, and keeps `/`, `_`, `**`… from triggering
/// menus or markdown formatting mid-code.
CharacterShortcutEvent skipInCodeBlock(CharacterShortcutEvent event) {
  return CharacterShortcutEvent(
    key: '${event.key} - skipped in code block',
    character: event.character,
    regExp: event.regExp,
    handler: (editorState) async {
      if (isInCodeBlock(editorState)) return false;
      return event.handler(editorState);
    },
    handlerWithCharacter: event.handlerWithCharacter == null
        ? null
        : (editorState, character) async {
            if (isInCodeBlock(editorState)) return false;
            return event.handlerWithCharacter!(editorState, character);
          },
  );
}

/// Typing the third backtick of ``` on an otherwise empty line converts the
/// paragraph into a code block.
final formatTripleBackquoteToCodeBlock = CharacterShortcutEvent(
  key: 'format ``` to code block',
  character: '`',
  handler: (editorState) async => formatMarkdownSymbol(
    editorState,
    (node) => node.type != CodeBlockKeys.type,
    (node, text, selection) =>
        text == '``' && node.delta?.toPlainText() == '``',
    (_, node, _) => [
      codeBlockNode(),
      if (node.children.isNotEmpty) ...node.children,
    ],
  ),
);

/// Tab inside a code block indents with two spaces instead of indenting the
/// whole block.
final codeBlockIndentCommand = CommandShortcutEvent(
  key: 'insert two spaces in code block',
  getDescription: () => 'Insert two spaces inside a code block',
  command: 'tab',
  handler: (editorState) {
    if (!isInCodeBlock(editorState)) return KeyEventResult.ignored;
    editorState.insertTextAtCurrentSelection('  ');
    return KeyEventResult.handled;
  },
);

/// Paste inside a code block keeps the raw text (newlines included) instead of
/// letting the standard paste split it into paragraphs.
final codeBlockPasteCommand = CommandShortcutEvent(
  key: 'paste plain text in code block',
  getDescription: () => 'Paste as plain text inside a code block',
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: (editorState) {
    if (!isInCodeBlock(editorState)) return KeyEventResult.ignored;
    () async {
      final selection = editorState.selection;
      if (selection == null) return;
      if (!selection.isCollapsed) {
        await editorState.deleteSelection(selection);
      }
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text != null && text.isNotEmpty) {
        await editorState.insertTextAtCurrentSelection(text);
      }
    }();
    return KeyEventResult.handled;
  },
);

/// Shift+Enter exits the code block: inserts a paragraph right below and moves
/// the caret there (plain Enter inserts a newline inside the block).
final codeBlockExitCommand = CommandShortcutEvent(
  key: 'insert paragraph below code block',
  getDescription: () => 'Exit the code block by inserting a paragraph below',
  command: 'shift+enter',
  handler: (editorState) {
    if (!isInCodeBlock(editorState)) return KeyEventResult.ignored;
    final selection = editorState.selection!;
    final node = editorState.getNodeAtPath(selection.end.path)!;
    final transaction = editorState.transaction
      ..insertNode(node.path.next, paragraphNode())
      ..afterSelection = Selection.collapsed(Position(path: node.path.next));
    editorState.apply(transaction);
    return KeyEventResult.handled;
  },
);

/// All the code block command shortcuts, to prepend to the standard ones.
final codeBlockCommands = [
  codeBlockIndentCommand,
  codeBlockPasteCommand,
  codeBlockExitCommand,
];

/// "Code block" entry for the slash menu, wearing [icon] — Material's unless
/// the application has an icon set of its own.
SelectionMenuItem codeBlockMenuItem({IconData icon = Icons.code}) =>
    SelectionMenuItem.node(
      getName: () => t('Code block'),
      keywords: ['code', 'snippet', '```'],
      iconBuilder: (editorState, isSelected, style) => SelectionMenuIconWidget(
        icon: icon,
        isSelected: isSelected,
        style: style,
      ),
      nodeBuilder: (editorState, context) => codeBlockNode(),
      replace: (editorState, node) => node.delta?.isEmpty ?? false,
      updateSelection: (editorState, path, replaced, insertedBefore) =>
          Selection.collapsed(Position(path: path)),
    );
