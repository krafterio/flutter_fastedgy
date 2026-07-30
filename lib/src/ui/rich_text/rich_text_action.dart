/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import '../icons.dart';
import 'rich_text_clipboard.dart';
import 'rich_text_feature.dart';
import 'rich_text_paste.dart';

/// One thing a formatting strip can do, said without drawing anything.
///
/// Data, not a widget, and that is the point: the editor underneath ships one
/// set of items for a pointer and another for a thumb, drawn with its own
/// buttons, so the same strip offered two different things depending on the
/// device. Here what is offered is declared once and the drawing is somebody
/// else's — an application's buttons on an application's glyphs.
class RichTextAction {
  /// What it is, for a caller narrowing the strip down.
  final String id;

  final FastEdgyGlyph glyph;

  /// Read at each display, never once at declaration: a strip is declared while
  /// the app boots, and `t()` called then would answer before the translations
  /// are loaded and hand back the English key for good.
  final String Function() getLabel;

  /// Actions of one group stand together, groups are told apart by a rule.
  final int group;

  /// Whether what it does is already done to the text under the caret — a bold
  /// button over bold words.
  final bool Function(EditorState editorState) isActive;

  /// Whether it can be used at all right now: undo with nothing to undo.
  final bool Function(EditorState editorState) isEnabled;

  final Future<void> Function(EditorState editorState) run;

  const RichTextAction({
    required this.id,
    required this.glyph,
    required this.getLabel,
    required this.isActive,
    required this.run,
    this.group = 0,
    this.isEnabled = _always,
  });

  /// A mark carried by the text itself: bold, italic, and the rest.
  factory RichTextAction.mark({
    required String id,
    required FastEdgyGlyph glyph,
    required String Function() getLabel,
    required String attribute,
    int group = 0,
  }) => RichTextAction(
    id: id,
    glyph: glyph,
    getLabel: getLabel,
    group: group,
    isEnabled: _hasCaret,
    isActive: (editorState) {
      final selection = editorState.selection;

      if (selection == null) {
        return false;
      }

      return editorState
          .getNodesInSelection(selection)
          .allSatisfyInSelection(
            selection,
            (delta) =>
                delta.isNotEmpty &&
                delta.everyAttributes((attr) => attr[attribute] == true),
          );
    },
    run: (editorState) => editorState.toggleAttribute(attribute),
  );

  /// Turning the block the caret is in into another kind, and back to a
  /// paragraph when it is already that kind — a list button leaves the list.
  factory RichTextAction.block({
    required String id,
    required FastEdgyGlyph glyph,
    required String Function() getLabel,
    required String type,
    Map<String, dynamic> attributes = const {},
    int group = 0,
  }) => RichTextAction(
    id: id,
    glyph: glyph,
    getLabel: getLabel,
    group: group,
    isEnabled: _hasCaret,
    isActive: (editorState) => _nodeOf(editorState)?.type == type,
    run: (editorState) async {
      final selection = editorState.selection;
      final node = _nodeOf(editorState);

      if (selection == null || node == null) {
        return;
      }

      final becomes = node.type == type ? ParagraphBlockKeys.type : type;

      await editorState.formatNode(
        selection,
        (node) => node.copyWith(
          type: becomes,
          attributes: {
            ...node.attributes,
            if (becomes == type) ...attributes,
            blockComponentDelta: (node.delta ?? Delta()).toJson(),
          },
        ),
      );
    },
  );

  static Node? _nodeOf(EditorState editorState) {
    final selection = editorState.selection;

    return selection == null
        ? null
        : editorState.getNodeAtPath(selection.start.path);
  }

  static bool _always(EditorState editorState) => true;

  /// Anything acting on the text needs somewhere to act: a strip left standing
  /// over a document nobody is writing in offers only what does not — undo, and
  /// what a feature adds on its own terms.
  static bool _hasCaret(EditorState editorState) =>
      editorState.selection != null;
}

/// Whether there are words under the selection, rather than a bare caret.
bool _hasSelection(EditorState editorState) {
  final selection = editorState.selection;

  return selection != null && !selection.isCollapsed;
}

/// What a formatting strip offers, in groups meant to be picked from — the
/// same list whatever draws it, and whatever it is drawn on.
class RichTextActions {
  RichTextActions._();

  /// What the system offers over its own text fields, which it does not offer
  /// here: the editor is a document, not a field the platform draws a callout
  /// for, and it takes cut, copy and paste from the keyboard alone.
  ///
  /// Cut and copy stand down with nothing selected, where they would say
  /// nothing; paste and select all are always there, which is the whole point
  /// — pasting happens with a bare caret far more often than into a selection.
  ///
  /// Last on the strip: what a writer reaches for while writing is the marks,
  /// and they belong under the thumb rather than pushed off the right edge.
  ///
  /// [features] because what is pasted comes back as the blocks this document
  /// knows how to hold, rather than as the characters it was.
  static List<RichTextAction> clipboard(RichTextFeatures features) => [
    RichTextAction(
      id: 'cut',
      glyph: FastEdgyGlyph.cut,
      getLabel: () => t('Cut'),
      group: 6,
      isActive: (_) => false,
      isEnabled: _hasSelection,
      run: (editorState) async => cutCommand.handler(editorState),
    ),
    RichTextAction(
      id: 'copy',
      glyph: FastEdgyGlyph.copy,
      getLabel: () => t('Copy'),
      group: 6,
      isActive: (_) => false,
      isEnabled: _hasSelection,
      run: (editorState) async => copyCommand.handler(editorState),
    ),
    RichTextAction(
      id: 'paste',
      glyph: FastEdgyGlyph.paste,
      getLabel: () => t('Paste'),
      group: 6,
      isActive: (_) => false,
      // Live only when the platform says there is text to paste — see
      // refreshRichTextClipboard for why it is asked that way.
      isEnabled: (editorState) =>
          RichTextAction._hasCaret(editorState) &&
          richTextClipboardHasContent.value,
      run: (editorState) => pasteRichText(editorState, features: features),
    ),
    RichTextAction(
      id: 'select_all',
      glyph: FastEdgyGlyph.selectAll,
      getLabel: () => t('Select all'),
      group: 6,
      isActive: (_) => false,
      isEnabled: RichTextAction._hasCaret,
      run: (editorState) async => selectAllCommand.handler(editorState),
    ),
  ];

  /// Marks carried by the text itself.
  static List<RichTextAction> get marks => [
    RichTextAction.mark(
      id: 'bold',
      glyph: FastEdgyGlyph.bold,
      getLabel: () => t('Bold'),
      attribute: AppFlowyRichTextKeys.bold,
      group: 1,
    ),
    RichTextAction.mark(
      id: 'italic',
      glyph: FastEdgyGlyph.italic,
      getLabel: () => t('Italic'),
      attribute: AppFlowyRichTextKeys.italic,
      group: 1,
    ),
    RichTextAction.mark(
      id: 'underline',
      glyph: FastEdgyGlyph.underline,
      getLabel: () => t('Underline'),
      attribute: AppFlowyRichTextKeys.underline,
      group: 1,
    ),
    RichTextAction.mark(
      id: 'strikethrough',
      glyph: FastEdgyGlyph.strikethrough,
      getLabel: () => t('Strikethrough'),
      attribute: AppFlowyRichTextKeys.strikethrough,
      group: 1,
    ),
  ];

  /// The three lists, each leaving the list when pressed again.
  static List<RichTextAction> get lists => [
    RichTextAction.block(
      id: 'todo_list',
      glyph: FastEdgyGlyph.todoList,
      getLabel: () => t('To-do list'),
      type: TodoListBlockKeys.type,
      attributes: const {TodoListBlockKeys.checked: false},
      group: 2,
    ),
    RichTextAction.block(
      id: 'bulleted_list',
      glyph: FastEdgyGlyph.bulletedList,
      getLabel: () => t('Bulleted list'),
      type: BulletedListBlockKeys.type,
      group: 2,
    ),
    RichTextAction.block(
      id: 'numbered_list',
      glyph: FastEdgyGlyph.numberedList,
      getLabel: () => t('Numbered list'),
      type: NumberedListBlockKeys.type,
      group: 2,
    ),
  ];

  /// Turning the block into a heading, or into a quote.
  static List<RichTextAction> get blockTypes => [
    RichTextAction.block(
      id: 'heading',
      glyph: FastEdgyGlyph.heading,
      getLabel: () => t('Heading'),
      type: HeadingBlockKeys.type,
      attributes: const {HeadingBlockKeys.level: 2},
      group: 3,
    ),
    RichTextAction.block(
      id: 'quote',
      glyph: FastEdgyGlyph.quote,
      getLabel: () => t('Quote'),
      type: QuoteBlockKeys.type,
      group: 3,
    ),
  ];

  /// A rule across the page.
  static List<RichTextAction> get insert => [
    RichTextAction(
      id: 'divider',
      glyph: FastEdgyGlyph.rule,
      getLabel: () => t('Divider'),
      group: 4,
      isActive: (_) => false,
      run: (editorState) async {
        final selection = editorState.selection;

        if (selection == null) {
          return;
        }

        await editorState.apply(
          editorState.transaction
            ..insertNode(selection.end.path.next, dividerNode())
            ..afterSelection = Selection.collapsed(
              Position(path: selection.end.path.next.next),
            ),
        );
      },
    ),
  ];

  /// The two ways back.
  static List<RichTextAction> get history => [
    RichTextAction(
      id: 'undo',
      glyph: FastEdgyGlyph.undo,
      getLabel: () => t('Undo'),
      group: 5,
      isActive: (_) => false,
      isEnabled: (editorState) => editorState.undoManager.undoStack.isNonEmpty,
      run: (editorState) async => editorState.undoManager.undo(),
    ),
    RichTextAction(
      id: 'redo',
      glyph: FastEdgyGlyph.redo,
      getLabel: () => t('Redo'),
      group: 5,
      isActive: (_) => false,
      isEnabled: (editorState) => editorState.undoManager.redoStack.isNonEmpty,
      run: (editorState) async => editorState.undoManager.redo(),
    ),
  ];

  /// What a strip offers unless it is told otherwise.
  static List<RichTextAction> get standard => [
    ...marks,
    ...lists,
    ...blockTypes,
    ...insert,
    ...history,
  ];
}
