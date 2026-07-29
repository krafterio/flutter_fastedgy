/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../theme/component_theme.dart';
import '../theme/theme.dart';
import '../theme/theme_data.dart';

/// Everything the rich text stack draws with: the editor, the view, the blocks
/// and the surfaces they open.
///
/// Not a set of holes an application has to fill — every value derives from the
/// tokens, so the stack is fully drawable with nothing supplied. An application
/// then overrides what it wants, all of it or three colours.
@immutable
class RichTextTheme extends ComponentThemeData {
  /// A page's text: what a document is read at.
  final TextStyle blockText;

  /// A field's text, at body size, so a composer sits at the height a plain
  /// field would and a message reads like the rest of a thread.
  final TextStyle fieldText;

  /// A code block's text.
  final TextStyle codeText;

  /// The face inline code takes, applied onto whatever text surrounds it —
  /// null where the typography names no monospace family.
  final String? monoFontFamily;

  final Color ink;
  final Color mutedText;

  /// What a block sits on.
  final Color surface;

  /// Code blocks, chips, mention pills.
  final Color subtleSurface;

  final Color border;
  final Color subtleBorder;

  /// A border meant to be noticed: a focused field, an outline standing for a
  /// state rather than a separation.
  final Color strongBorder;

  /// A refusal — an invalid link, a value the editor will not take.
  final Color danger;

  /// A link's text. Underlined by the editor, so it carries the colour alone.
  final Color link;

  final Color cursor;

  /// What the editor lays over selected text. Anything else showing itself as
  /// selected wears the same, so a mixed selection reads as one.
  final Color selection;

  /// The selection over a block that carries a surface of its own.
  ///
  /// Kascade found its selection tint and its code-block card sitting four
  /// hundredths of luminance apart: a selected line inside a code block looked
  /// exactly like an unselected one, and nothing showed what was about to be
  /// deleted. Pushed toward the ink rather than recoloured — a selection running
  /// through a code block and the text around it still has to read as one
  /// selection, and toward-the-ink is the one direction that gains contrast
  /// whether the theme is light or dark.
  final Color selectionOnSurface;

  /// The same tint over something that has to stay visible through it.
  ///
  /// Behind glyphs a flat colour reads as a highlight; over a picture it is
  /// simply a lid. Only the transparency differs — the hue is the selection's,
  /// so both still read as one selection.
  final Color selectionVeil;

  /// Where a drop would land: a line the eye has to catch at a glance, so it
  /// stays darker than a focus border.
  final Color dropIndicator;

  final BorderRadius blockRadius;
  final BorderRadius chipRadius;
  final EdgeInsets blockPadding;

  /// What anything floating over the document wears — the toolbar, an editing
  /// card, a menu.
  ///
  /// Material elevation only shadows downwards, so a border and a second spread
  /// shadow are what keep a top edge visible against a pale surface.
  final BoxDecoration floatingSurface;

  const RichTextTheme({
    required this.blockText,
    required this.fieldText,
    required this.codeText,
    required this.ink,
    required this.mutedText,
    required this.surface,
    required this.subtleSurface,
    required this.border,
    required this.subtleBorder,
    required this.strongBorder,
    required this.danger,
    required this.link,
    required this.cursor,
    required this.selection,
    required this.selectionOnSurface,
    required this.selectionVeil,
    required this.dropIndicator,
    required this.blockRadius,
    required this.chipRadius,
    required this.blockPadding,
    required this.floatingSurface,
    this.monoFontFamily,
  });

  /// Derived from the tokens, so an application that overrides one role sees
  /// the whole stack follow instead of repeating a colour in five places.
  ///
  /// The text roles carry no colour of their own, so [ink] is painted onto them
  /// here; an application wanting its body text a shade off its strongest ink
  /// overrides [blockText] and [fieldText] with the exact styles it wants.
  factory RichTextTheme.from(FastEdgyThemeData theme) {
    final colors = theme.colors;

    return RichTextTheme(
      blockText: theme.typography.blockText.copyWith(color: colors.ink),
      fieldText: theme.typography.body.copyWith(color: colors.ink),
      codeText: theme.typography.mono.copyWith(color: colors.ink),
      monoFontFamily: theme.typography.mono.fontFamily,
      ink: colors.ink,
      mutedText: colors.muted,
      surface: colors.surface,
      subtleSurface: colors.subtleSurface,
      border: colors.border,
      subtleBorder: colors.subtleBorder,
      strongBorder: Color.alphaBlend(
        colors.ink.withValues(alpha: 0.20),
        colors.border,
      ),
      danger: colors.danger,
      link: colors.accent,
      cursor: colors.cursor,
      selection: colors.selection,
      selectionOnSurface: Color.alphaBlend(
        colors.ink.withValues(alpha: 0.10),
        colors.selection,
      ),
      selectionVeil: colors.selection.withValues(alpha: 0.45),
      dropIndicator: colors.muted,
      blockRadius: BorderRadius.circular(theme.radius),
      chipRadius: BorderRadius.circular(theme.radius / 2),
      blockPadding: EdgeInsets.symmetric(
        horizontal: theme.spacing * 3,
        vertical: theme.spacing * 2,
      ),
      floatingSurface: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(theme.radius),
        border: Border.all(color: colors.subtleBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.10),
            blurRadius: 6,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
    );
  }

  /// What the package draws with when no application has said anything at all.
  static final RichTextTheme fallback = RichTextTheme.from(
    FastEdgyThemeData.fallback,
  );

  /// The theme in scope: what the application registered, else what the tokens
  /// give. Never null, and never a design decision the application did not make.
  static RichTextTheme of(BuildContext context) {
    return ComponentTheme.maybeOf<RichTextTheme>(context) ??
        RichTextTheme.from(FastEdgyTheme.of(context));
  }

  RichTextTheme copyWith({
    TextStyle? blockText,
    TextStyle? fieldText,
    TextStyle? codeText,
    String? monoFontFamily,
    Color? ink,
    Color? mutedText,
    Color? surface,
    Color? subtleSurface,
    Color? border,
    Color? subtleBorder,
    Color? strongBorder,
    Color? danger,
    Color? link,
    Color? cursor,
    Color? selection,
    Color? selectionOnSurface,
    Color? selectionVeil,
    Color? dropIndicator,
    BorderRadius? blockRadius,
    BorderRadius? chipRadius,
    EdgeInsets? blockPadding,
    BoxDecoration? floatingSurface,
  }) {
    return RichTextTheme(
      blockText: blockText ?? this.blockText,
      fieldText: fieldText ?? this.fieldText,
      codeText: codeText ?? this.codeText,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
      ink: ink ?? this.ink,
      mutedText: mutedText ?? this.mutedText,
      surface: surface ?? this.surface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      border: border ?? this.border,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      strongBorder: strongBorder ?? this.strongBorder,
      danger: danger ?? this.danger,
      link: link ?? this.link,
      cursor: cursor ?? this.cursor,
      selection: selection ?? this.selection,
      selectionOnSurface: selectionOnSurface ?? this.selectionOnSurface,
      selectionVeil: selectionVeil ?? this.selectionVeil,
      dropIndicator: dropIndicator ?? this.dropIndicator,
      blockRadius: blockRadius ?? this.blockRadius,
      chipRadius: chipRadius ?? this.chipRadius,
      blockPadding: blockPadding ?? this.blockPadding,
      floatingSurface: floatingSurface ?? this.floatingSurface,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is RichTextTheme &&
        other.blockText == blockText &&
        other.fieldText == fieldText &&
        other.codeText == codeText &&
        other.monoFontFamily == monoFontFamily &&
        other.ink == ink &&
        other.mutedText == mutedText &&
        other.surface == surface &&
        other.subtleSurface == subtleSurface &&
        other.border == border &&
        other.subtleBorder == subtleBorder &&
        other.strongBorder == strongBorder &&
        other.danger == danger &&
        other.link == link &&
        other.cursor == cursor &&
        other.selection == selection &&
        other.selectionOnSurface == selectionOnSurface &&
        other.selectionVeil == selectionVeil &&
        other.dropIndicator == dropIndicator &&
        other.blockRadius == blockRadius &&
        other.chipRadius == chipRadius &&
        other.blockPadding == blockPadding &&
        other.floatingSurface == floatingSurface;
  }

  @override
  int get hashCode => Object.hashAll([
    blockText,
    fieldText,
    codeText,
    monoFontFamily,
    ink,
    mutedText,
    surface,
    subtleSurface,
    border,
    subtleBorder,
    strongBorder,
    danger,
    link,
    cursor,
    selection,
    selectionOnSurface,
    selectionVeil,
    dropIndicator,
    blockRadius,
    chipRadius,
    blockPadding,
    floatingSurface,
  ]);
}
