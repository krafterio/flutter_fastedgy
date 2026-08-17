/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';

import '../../rich_text_feature.dart';

import 'code_block_component.dart';
import 'code_block_markdown.dart';
import 'code_block_shortcuts.dart';

/// Code block: a grey card with syntax highlighting and a language selector.
class CodeBlockFeature extends RichTextFeature {
  /// The glyph on the "/" menu entry. An argument rather than a theme: the
  /// entry is built inside an overlay the underlying editor creates, out of
  /// reach of anything inherited. What the block draws itself reads
  /// [FastEdgyIcons] from the context like the rest.
  final IconData menuIcon;

  /// False withdraws every way of making one and keeps everything that reads
  /// one. Dropping the feature instead takes the reading with it.
  final bool offered;

  const CodeBlockFeature({this.menuIcon = Icons.code, this.offered = true});

  @override
  Map<String, BlockComponentBuilder> get builders => {
    CodeBlockKeys.type: CodeBlockComponentBuilder(),
  };

  @override
  List<SelectionMenuItem> get menuItems =>
      offered ? [codeBlockMenuItem(icon: menuIcon)] : const [];

  @override
  List<CharacterShortcutEvent> get characterShortcuts =>
      offered ? [formatTripleBackquoteToCodeBlock] : const [];

  @override
  List<CommandShortcutEvent> get commandShortcuts => codeBlockCommands;

  /// Typing inside a code block writes characters: no Enter splitting the
  /// block, no markdown trigger formatting it, no "/" menu opening in it.
  @override
  CharacterShortcutEvent guard(CharacterShortcutEvent event) =>
      skipInCodeBlock(event);

  /// A line of code is a line, wherever the block is written — in a composer
  /// that otherwise sends on Enter as much as on a page.
  @override
  bool holdsEnter(EditorState editorState) => isInCodeBlock(editorState);

  /// Declared even though the package encodes `code` out of the box: a feature
  /// owns both ends of its round trip, and the package dropping its parser
  /// would otherwise silently stop saving the block.
  @override
  List<NodeParser> get markdownEncoders => const [CodeBlockNodeParser()];

  @override
  List<CustomMarkdownParser> get markdownDecoders => const [
    MarkdownCodeBlockParser(),
  ];
}
