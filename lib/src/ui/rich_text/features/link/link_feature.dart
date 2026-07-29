/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../../rich_text_feature.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'link_gestures.dart';
import 'link_markdown.dart';
import 'link_menu.dart';

/// Turning a selection into a link, and editing the link it already is.
///
/// Replaces the package's own item: its menu and its placement both live under
/// `src/`, so restyling it meant rebuilding it. The id is kept — it is what the
/// toolbar identifies the item by.
class LinkFeature extends RichTextFeature {
  const LinkFeature();

  static const id = 'editor.link';

  /// A link is reached by more than the toolbar — clicking one, Cmd+K — and
  /// every route has to land on our card, or the package's English menu shows
  /// up for the same link depending on how it was opened.
  @override
  TextSpanDecoratorForAttribute? get textSpanDecorator => linkTextSpanDecorator;

  @override
  List<CommandShortcutEvent> get commandShortcuts => [linkShortcut];

  @override
  Document beforeMarkdown(Document document) => withoutSelfLinks(document);

  @override
  List<ToolbarItem> get toolbarItems => [
    ToolbarItem(
      id: id,
      group: 4,
      isActive: onlyShowInSingleSelectionAndTextType,
      builder:
          (context, editorState, highlightColor, iconColor, tooltipBuilder) {
            final selection = editorState.selection!;
            final isLink = editorState
                .getNodesInSelection(selection)
                .allSatisfyInSelection(
                  selection,
                  (delta) => delta.everyAttributes(
                    (attributes) =>
                        attributes[AppFlowyRichTextKeys.href] != null,
                  ),
                );

            final child = SVGIconItemWidget(
              iconName: 'toolbar/link',
              isHighlight: isLink,
              highlightColor: highlightColor,
              iconColor: iconColor,
              onPressed: () => showLinkEditor(context, editorState, selection),
            );

            return tooltipBuilder?.call(context, id, t('Link'), child) ?? child;
          },
    ),
  ];
}
