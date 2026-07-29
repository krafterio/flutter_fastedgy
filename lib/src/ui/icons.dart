/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/material.dart';

import 'theme/component_theme.dart';

/// Every glyph the UI module draws, named by what it means.
///
/// An enum rather than a field per glyph: the set grows with each feature, and
/// a class of twenty fields with a twenty-parameter `copyWith` grows with it.
enum FastEdgyGlyph {
  /// A ticked box, a chosen option.
  check,

  copy,

  /// The copy button in the instant after it was pressed.
  copied,

  /// The field holding a link's visible text.
  title,

  link,

  /// Leaving the app to follow a link.
  openExternal,

  unlink,

  /// Adding a row or a column to a table.
  add,

  insertLeft,
  insertRight,
  insertAbove,
  insertBelow,

  duplicate,

  /// Emptying something without removing it.
  clear,

  delete,

  /// What a row and a column are dragged by.
  gripRow,
  gripColumn,

  /// Choosing a picture.
  image,

  /// A picture that could not be read.
  imageMissing,

  close,
  download,

  /// Putting a zoomed picture back where it started.
  resetZoom,

  previous,
  next,
}

const Map<FastEdgyGlyph, IconData> _material = {
  FastEdgyGlyph.check: Icons.check,
  FastEdgyGlyph.copy: Icons.copy,
  FastEdgyGlyph.copied: Icons.check,
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
  // Turned the way each is dragged, and distinct: a row grip and a column
  // grip drawn alike are two affordances nobody can tell apart.
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

/// The glyphs the UI module draws, in one place.
///
/// Material's by default, so a package that must never name an icon set still
/// draws something. An application mounts its own once and every block, card
/// and button follows — which is also what keeps a copy button and a link's
/// copy action wearing the same mark.
///
/// **Not** the "/" menu entries: those are built by the underlying editor
/// inside an overlay it creates itself, where an inherited theme is out of
/// reach. Their glyphs stay arguments on the feature that declares them.
@immutable
class FastEdgyIcons extends ComponentThemeData {
  /// Only what the application chose to name. Everything else falls through to
  /// Material, so naming two glyphs is not naming the seventeen.
  final Map<FastEdgyGlyph, IconData> glyphs;

  const FastEdgyIcons([this.glyphs = const {}]);

  static const FastEdgyIcons material = FastEdgyIcons();

  static FastEdgyIcons of(BuildContext context) {
    return ComponentTheme.maybeOf<FastEdgyIcons>(context) ?? material;
  }

  IconData operator [](FastEdgyGlyph glyph) =>
      glyphs[glyph] ?? _material[glyph]!;

  FastEdgyIcons copyWith(Map<FastEdgyGlyph, IconData> overrides) {
    return FastEdgyIcons({...glyphs, ...overrides});
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is FastEdgyIcons &&
        other.glyphs.length == glyphs.length &&
        other.glyphs.entries.every((e) => glyphs[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    glyphs.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
