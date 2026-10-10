/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Icons;

/// The `Icons` each glyph is drawn with by default: the package declares them
/// by their code point, so that drawing them imports no Material.
const _twins = {
  FastEdgyGlyph.slash: Icons.dnd_forwardslash,
  FastEdgyGlyph.bold: Icons.format_bold,
  FastEdgyGlyph.italic: Icons.format_italic,
  FastEdgyGlyph.underline: Icons.format_underlined,
  FastEdgyGlyph.strikethrough: Icons.format_strikethrough,
  FastEdgyGlyph.code: Icons.code,
  FastEdgyGlyph.heading1: Icons.title,
  FastEdgyGlyph.heading2: Icons.format_size,
  FastEdgyGlyph.heading3: Icons.text_fields,
  FastEdgyGlyph.table: Icons.table_chart_outlined,
  FastEdgyGlyph.quote: Icons.format_quote,
  FastEdgyGlyph.bulletedList: Icons.format_list_bulleted,
  FastEdgyGlyph.numberedList: Icons.format_list_numbered,
  FastEdgyGlyph.todoList: Icons.checklist,
  FastEdgyGlyph.rule: Icons.horizontal_rule,
  FastEdgyGlyph.undo: Icons.undo,
  FastEdgyGlyph.redo: Icons.redo,
  FastEdgyGlyph.check: Icons.check,
  FastEdgyGlyph.copy: Icons.copy,
  FastEdgyGlyph.copied: Icons.check,
  FastEdgyGlyph.cut: Icons.content_cut,
  FastEdgyGlyph.paste: Icons.content_paste,
  FastEdgyGlyph.selectAll: Icons.select_all,
  FastEdgyGlyph.title: Icons.title,
  FastEdgyGlyph.link: Icons.link,
  FastEdgyGlyph.openExternal: Icons.open_in_new,
  FastEdgyGlyph.unlink: Icons.link_off,
  FastEdgyGlyph.add: Icons.add,
  FastEdgyGlyph.insertLeft: Icons.keyboard_tab,
  FastEdgyGlyph.insertRight: Icons.keyboard_tab,
  FastEdgyGlyph.insertAbove: Icons.vertical_align_top,
  FastEdgyGlyph.insertBelow: Icons.vertical_align_bottom,
  FastEdgyGlyph.duplicate: Icons.content_copy,
  FastEdgyGlyph.clear: Icons.backspace_outlined,
  FastEdgyGlyph.delete: Icons.delete_outline,
  FastEdgyGlyph.gripRow: Icons.drag_indicator,
  FastEdgyGlyph.gripColumn: Icons.drag_handle,
  FastEdgyGlyph.image: Icons.image_outlined,
  FastEdgyGlyph.imageMissing: Icons.broken_image_outlined,
  FastEdgyGlyph.close: Icons.close,
  FastEdgyGlyph.download: Icons.download,
  FastEdgyGlyph.resetZoom: Icons.restart_alt,
  FastEdgyGlyph.previous: Icons.chevron_left,
  FastEdgyGlyph.next: Icons.chevron_right,
};

void main() {
  test('draws each glyph by default with the Material icon it stands for', () {
    expect(_twins.keys.toSet(), FastEdgyGlyph.values.toSet());

    for (final glyph in FastEdgyGlyph.values) {
      expect(FastEdgyIcons.material[glyph], _twins[glyph], reason: '$glyph');
    }
  });
}
