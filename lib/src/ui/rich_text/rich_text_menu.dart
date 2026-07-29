/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart' show IconData, Widget;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'rich_text_feature.dart';

const _ourNames = {
  'Bulleted List': 'Bulleted list',
  'Numbered List': 'Numbered list',
};

String richTextMenuLabel(String upstreamName) =>
    _ourNames[upstreamName] ?? upstreamName;

/// The "/" menu: the package's blocks first, then what the features add.
/// The package names its items from `AppFlowyEditorL10n`, an English-only
/// catalog the app never configures — hence a menu that stayed in English. Its
/// labels being plain English text is exactly how our own keys are written, so
/// [icons] swaps the glyph on an upstream item, keyed by the English label the
/// package ships ('Divider'), so a menu stays on the host application's icon set
/// without the module knowing one.
List<SelectionMenuItem> richTextSlashMenuItems(
  RichTextFeatures features, {
  Map<String, IconData> icons = const {},
}) => [
  for (final item in standardSelectionMenuItems)
    if (!features.replacedMenuItems.contains(item.name))
      _translated(item, icons[item.name]),
  ...features.menuItems,
];

SelectionMenuItem _translated(SelectionMenuItem item, IconData? icon) {
  final label = item.name;

  // Both this item and the one it wraps would delete the "/" that opened the
  // menu, and the second would find none left — an out-of-range delete on an
  // otherwise empty paragraph. Only one may be armed, and it cannot be ours:
  // the menu overwrites these flags on the items it is handed (see
  // SelectionMenuWidget, `element.deleteSlash = deleteSlashByDefault`), so a
  // wrapper opting out is re-armed behind its back. The wrapped one stands
  // down instead, being the one the menu never sees.
  item
    ..deleteSlash = false
    ..deleteKeywords = false;

  return SelectionMenuItem(
    getName: () => t(richTextMenuLabel(label)),
    icon: icon == null ? item.icon : _iconWidget(icon),
    keywords: item.keywords,
    handler: item.handler,
  );
}

Widget Function(EditorState, bool, SelectionMenuStyle) _iconWidget(
  IconData icon,
) =>
    (editorState, isSelected, style) => SelectionMenuIconWidget(
      icon: icon,
      isSelected: isSelected,
      style: style,
    );
