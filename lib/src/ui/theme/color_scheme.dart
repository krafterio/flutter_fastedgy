/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

/// What a colour is *for*, never what it is.
///
/// An application maps these roles onto its palette; no widget of the framework
/// ever names a hue. A role earns its place only if a framework widget can name
/// it without naming a product — anything with a business meaning (a status, a
/// priority) belongs to the application's own [ComponentThemeData].
@immutable
class ColorRoles {
  /// The strongest text, and anything meant to read as foreground.
  final Color ink;

  /// Placeholders, hints, secondary labels — present but not competing.
  final Color muted;

  /// What content sits on.
  final Color surface;

  /// A card, a chip, a code block: raised off [surface] without a border.
  final Color subtleSurface;

  /// A separation meant to be seen.
  final Color border;

  /// A separation meant to be felt rather than seen.
  final Color subtleBorder;

  /// What the product is recognised by, and what a primary action wears.
  final Color accent;

  /// Text and glyphs drawn on top of [accent].
  final Color onAccent;

  /// Destruction, refusal, a failed operation.
  final Color danger;

  /// A completed operation.
  final Color success;

  /// The wash behind selected text. Expected to be translucent, since it is
  /// painted over whatever the text sits on.
  final Color selection;

  /// The caret.
  final Color cursor;

  const ColorRoles({
    required this.ink,
    required this.muted,
    required this.surface,
    required this.subtleSurface,
    required this.border,
    required this.subtleBorder,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.selection,
    required this.cursor,
  });

  /// A floor, not a look: plain enough that nothing crashes before an
  /// application has spoken, and plain enough that nobody ships it by accident.
  static const ColorRoles fallback = ColorRoles(
    ink: Color(0xFF1A1A1A),
    muted: Color(0xFF767676),
    surface: Color(0xFFFFFFFF),
    subtleSurface: Color(0xFFF4F4F5),
    border: Color(0xFFD4D4D8),
    subtleBorder: Color(0xFFE4E4E7),
    accent: Color(0xFF3F3F46),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFB91C1C),
    success: Color(0xFF15803D),
    selection: Color(0x333F3F46),
    cursor: Color(0xFF1A1A1A),
  );

  ColorRoles copyWith({
    Color? ink,
    Color? muted,
    Color? surface,
    Color? subtleSurface,
    Color? border,
    Color? subtleBorder,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? success,
    Color? selection,
    Color? cursor,
  }) {
    return ColorRoles(
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      surface: surface ?? this.surface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      border: border ?? this.border,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      selection: selection ?? this.selection,
      cursor: cursor ?? this.cursor,
    );
  }

  static ColorRoles lerp(ColorRoles a, ColorRoles b, double t) {
    return ColorRoles(
      ink: Color.lerp(a.ink, b.ink, t)!,
      muted: Color.lerp(a.muted, b.muted, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      subtleSurface: Color.lerp(a.subtleSurface, b.subtleSurface, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      subtleBorder: Color.lerp(a.subtleBorder, b.subtleBorder, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
      danger: Color.lerp(a.danger, b.danger, t)!,
      success: Color.lerp(a.success, b.success, t)!,
      selection: Color.lerp(a.selection, b.selection, t)!,
      cursor: Color.lerp(a.cursor, b.cursor, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ColorRoles &&
        other.ink == ink &&
        other.muted == muted &&
        other.surface == surface &&
        other.subtleSurface == subtleSurface &&
        other.border == border &&
        other.subtleBorder == subtleBorder &&
        other.accent == accent &&
        other.onAccent == onAccent &&
        other.danger == danger &&
        other.success == success &&
        other.selection == selection &&
        other.cursor == cursor;
  }

  @override
  int get hashCode => Object.hash(
    ink,
    muted,
    surface,
    subtleSurface,
    border,
    subtleBorder,
    accent,
    onAccent,
    danger,
    success,
    selection,
    cursor,
  );
}
