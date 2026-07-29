/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';

/// What the toolbar floating over a selection can offer, in groups meant to be
/// picked from: a page wants them all, a comment box may want the marks alone.
///
/// Whatever a [RichTextEditor] is given, the features it carries append their
/// own items after it — narrow the features to drop those.
class RichTextToolbar {
  RichTextToolbar._();

  /// Turning the block into another kind: plain text, the three heading levels.
  static List<ToolbarItem> get blockTypes => [paragraphItem, ...headingItems];

  /// Marks carried by the text itself: bold, italic, underline, strikethrough.
  ///
  /// The package's inline code is left out on purpose — code goes through our
  /// code block, and two ways of writing code read as a bug.
  static List<ToolbarItem> get marks => markdownFormatItems
      .where((item) => item.id != 'editor.code')
      .toList(growable: false);

  static List<ToolbarItem> get quote => [quoteItem];

  static List<ToolbarItem> get lists => [bulletedListItem, numberedListItem];

  /// What an editor floats unless it is told otherwise.
  static List<ToolbarItem> get standard => [
    ...blockTypes,
    ...marks,
    ...quote,
    ...lists,
  ];
}
