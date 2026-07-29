/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../rich_text_feature.dart';
import '../../icons.dart';
import '../rich_text_theme.dart';

/// The editor's todo list, with a checkbox drawn from the theme in place of its
/// blue check icon.
class TodoListFeature extends RichTextFeature {
  const TodoListFeature();

  @override
  Map<String, BlockComponentBuilder> get builders => {
    TodoListBlockKeys.type: TodoListBlockComponentBuilder(
      iconBuilder: _iconBuilder,
    ),
  };

  Widget _iconBuilder(BuildContext context, Node node, VoidCallback onCheck) {
    final checked = node.attributes[TodoListBlockKeys.checked] == true;
    final theme = RichTextTheme.of(context);
    final icons = FastEdgyIcons.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCheck,
        child: Container(
          constraints: const BoxConstraints(minWidth: 26, minHeight: 22),
          padding: const EdgeInsets.only(right: 4),
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: checked ? theme.ink : theme.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: checked ? theme.ink : theme.strongBorder,
                width: 1.5,
              ),
            ),
            child: checked
                ? Icon(
                    icons[FastEdgyGlyph.check],
                    size: 11,
                    color: theme.surface,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
