/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

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

  cut,
  paste,
  selectAll,

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

  /// The character that opens the list of blocks, drawn as itself: a strip of
  /// actions offers it where there is no keyboard to type it on.
  slash,

  /// What a formatting strip offers: marks carried by the text, block kinds it
  /// can be turned into, and the two ways back.
  bold,
  italic,
  underline,
  strikethrough,

  /// Code carried by the text itself, as opposed to a block of it.
  code,

  /// Text
  heading1,
  heading2,
  heading3,
  table,
  quote,
  bulletedList,
  numberedList,
  todoList,
  rule,
  undo,
  redo,
}

// Material's glyphs, by their code point in the MaterialIcons font a Flutter
// app bundles (`uses-material-design`): the marks of `Icons`, without
// importing Material. A test holds each one to its `Icons` twin.
const _materialFont = 'MaterialIcons';

const Map<FastEdgyGlyph, IconData> _material = {
  // Material ships no bare slash; this is the only glyph it has that draws one,
  // circle and all. Distinct from `add` on purpose — sharing that one would put
  // the same picture on "insert a block" and on "add a row". An application
  // with its own icon set gives this the character itself.
  FastEdgyGlyph.slash: IconData(0xe1eb, fontFamily: _materialFont),
  FastEdgyGlyph.bold: IconData(0xe2af, fontFamily: _materialFont),
  FastEdgyGlyph.italic: IconData(0xe2b6, fontFamily: _materialFont),
  FastEdgyGlyph.underline: IconData(0xe2c2, fontFamily: _materialFont),
  FastEdgyGlyph.strikethrough: IconData(0xe2bf, fontFamily: _materialFont),
  FastEdgyGlyph.code: IconData(0xe176, fontFamily: _materialFont),
  // Material ships no H1 and no H2; `title` is the one glyph it has for a
  // heading at all. An application with its own set draws the two apart.
  FastEdgyGlyph.heading1: IconData(0xe668, fontFamily: _materialFont),
  FastEdgyGlyph.heading2: IconData(0xe2be, fontFamily: _materialFont),
  FastEdgyGlyph.heading3: IconData(0xe649, fontFamily: _materialFont),
  FastEdgyGlyph.table: IconData(0xf41d, fontFamily: _materialFont),
  FastEdgyGlyph.quote: IconData(0xe2bc, fontFamily: _materialFont),
  FastEdgyGlyph.bulletedList: IconData(
    0xe2b8,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.numberedList: IconData(0xe2b9, fontFamily: _materialFont),
  FastEdgyGlyph.todoList: IconData(0xe15b, fontFamily: _materialFont),
  FastEdgyGlyph.rule: IconData(0xe31f, fontFamily: _materialFont),
  FastEdgyGlyph.undo: IconData(
    0xe68c,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.redo: IconData(
    0xe512,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.check: IconData(0xe156, fontFamily: _materialFont),
  FastEdgyGlyph.copy: IconData(0xe190, fontFamily: _materialFont),
  FastEdgyGlyph.copied: IconData(0xe156, fontFamily: _materialFont),
  FastEdgyGlyph.cut: IconData(0xe191, fontFamily: _materialFont),
  FastEdgyGlyph.paste: IconData(0xe192, fontFamily: _materialFont),
  FastEdgyGlyph.selectAll: IconData(0xe56e, fontFamily: _materialFont),
  FastEdgyGlyph.title: IconData(0xe668, fontFamily: _materialFont),
  FastEdgyGlyph.link: IconData(0xe380, fontFamily: _materialFont),
  FastEdgyGlyph.openExternal: IconData(
    0xe45c,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.unlink: IconData(0xe381, fontFamily: _materialFont),
  FastEdgyGlyph.add: IconData(0xe047, fontFamily: _materialFont),
  FastEdgyGlyph.insertLeft: IconData(
    0xe35b,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.insertRight: IconData(
    0xe35b,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.insertAbove: IconData(0xe69d, fontFamily: _materialFont),
  FastEdgyGlyph.insertBelow: IconData(0xe69b, fontFamily: _materialFont),
  FastEdgyGlyph.duplicate: IconData(0xe190, fontFamily: _materialFont),
  FastEdgyGlyph.clear: IconData(
    0xeeb5,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.delete: IconData(0xe1bb, fontFamily: _materialFont),
  // Turned the way each is dragged, and distinct: a row grip and a column
  // grip drawn alike are two affordances nobody can tell apart.
  FastEdgyGlyph.gripRow: IconData(0xe207, fontFamily: _materialFont),
  FastEdgyGlyph.gripColumn: IconData(0xe206, fontFamily: _materialFont),
  FastEdgyGlyph.image: IconData(0xf120, fontFamily: _materialFont),
  FastEdgyGlyph.imageMissing: IconData(0xeeff, fontFamily: _materialFont),
  FastEdgyGlyph.close: IconData(0xe16a, fontFamily: _materialFont),
  FastEdgyGlyph.download: IconData(0xe201, fontFamily: _materialFont),
  FastEdgyGlyph.resetZoom: IconData(0xe531, fontFamily: _materialFont),
  FastEdgyGlyph.previous: IconData(
    0xe15e,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
  FastEdgyGlyph.next: IconData(
    0xe15f,
    fontFamily: _materialFont,
    matchTextDirection: true,
  ),
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
