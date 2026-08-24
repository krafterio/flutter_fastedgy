/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'rich_text_codec.dart';
import 'rich_text_feature.dart';

/// Whether the clipboard holds anything worth offering to paste.
///
/// Kept rather than asked at each build because asking is asynchronous and a
/// button has to say whether it is live while it is being drawn. Starts as
/// true: a paste button greyed out because nothing has been read yet would be
/// wrong more often than right.
final richTextClipboardHasContent = ValueNotifier<bool>(true);

/// Asks the platform whether there is text to paste, without asking for the
/// text.
///
/// `hasStrings` and not `getData`, and this is the whole reason the value is
/// kept at all: reading the clipboard on iOS raises the system's "Allow paste?"
/// prompt, and a strip that read it to grey out a button would raise that
/// prompt every time it appeared. Asking whether there *is* something raises
/// nothing.
Future<void> refreshRichTextClipboard() async {
  try {
    richTextClipboardHasContent.value = await Clipboard.hasStrings();
  } on PlatformException {
    // A platform that will not answer is one where the button is better left
    // live: pressing it is then the only way to find out, which is what every
    // editor did before this.
    richTextClipboardHasContent.value = true;
  }
}

/// Copy, writing what was selected under every shape it is read in.
///
/// The package writes the bare words, so everything copied came back plain:
/// bold pasted as plain text, a list as three loose lines, even into the
/// editor it was copied from.
///
/// Written twice instead, and a reader takes its own: markdown, which an
/// editor of ours reads back as the blocks it describes (see `pasteRichText`)
/// and a plain editor shows as text, and html, which a word processor pastes
/// as formatted text.
Future<void> copyRichText(
  EditorState editorState, {
  required RichTextFeatures features,
}) async {
  final selection = editorState.selection?.normalized;

  if (selection == null || selection.isCollapsed) {
    return;
  }

  final nodes = editorState.getSelectedNodes(selection: selection);
  final document = Document.blank()..insert([0], nodes);
  final markdown = MarkdownRichTextCodec(features: features)
      .encode(document)
      .trimRight();

  if (markdown.isEmpty) {
    return;
  }

  await writeRichTextClipboard(
    markdown: markdown,
    html: documentToHTML(document),
  );
}

/// The one channel a platform implements to carry more than one flavour.
///
/// A pasteboard holds what was copied under several shapes at once and each
/// reader takes the one it understands; Flutter's own clipboard carries text
/// and nothing else, which is why this goes around it.
const _clipboardChannel = MethodChannel('fastedgy/clipboard');

/// Puts what was copied on the clipboard under both shapes it is read in.
///
/// [markdown] is what an editor of ours reads back as blocks and what a plain
/// text editor shows; [html] is what a word processor pastes as formatted
/// text. Both are written at once, and each reader takes its own.
///
/// A platform that implements nothing keeps the markdown alone, through the
/// package's clipboard: one flavour, and the one that reads back here.
Future<void> writeRichTextClipboard({
  required String markdown,
  required String html,
}) async {
  try {
    await _clipboardChannel.invokeMethod<void>('write', {
      'text': markdown,
      'html': html,
    });
  } on MissingPluginException {
    await AppFlowyClipboard.setData(text: markdown);
  } on PlatformException {
    await AppFlowyClipboard.setData(text: markdown);
  }
}

/// Copy, then take away what was copied.
Future<void> cutRichText(
  EditorState editorState, {
  required RichTextFeatures features,
}) async {
  await copyRichText(editorState, features: features);
  await deleteSelectedContent(editorState);
}

/// Stands ahead of the package's own copy, which writes the words alone.
CommandShortcutEvent richTextCopyCommand({
  required RichTextFeatures features,
}) => CommandShortcutEvent(
  key: 'copy as markdown',
  getDescription: () => t('Copy, keeping the formatting'),
  command: 'ctrl+c',
  macOSCommand: 'cmd+c',
  handler: (editorState) =>
      _handle(editorState, () => copyRichText(editorState, features: features)),
);

/// Stands ahead of the package's own cut, for the same reason.
CommandShortcutEvent richTextCutCommand({required RichTextFeatures features}) =>
    CommandShortcutEvent(
      key: 'cut as markdown',
      getDescription: () => t('Cut, keeping the formatting'),
      command: 'ctrl+x',
      macOSCommand: 'cmd+x',
      handler: (editorState) => _handle(
        editorState,
        () => cutRichText(editorState, features: features),
      ),
    );

KeyEventResult _handle(EditorState editorState, Future<void> Function() run) {
  final selection = editorState.selection;

  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  unawaited(run());

  return KeyEventResult.handled;
}
