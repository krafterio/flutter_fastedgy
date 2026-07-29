/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

/// What a text style is *for*, and only the ones a framework widget draws.
///
/// None of them carries a colour: a widget pairs a role here with a role from
/// [ColorRoles], so an application that recolours its text does it in one place
/// instead of five.
@immutable
class TypographyRoles {
  /// A field, a message, a row — text read in passing.
  final TextStyle body;

  /// A page, read at length: looser than [body] on purpose.
  final TextStyle blockText;

  /// Captions, hints, metadata.
  final TextStyle small;

  /// Code, and anything that must align by column.
  final TextStyle mono;

  /// A title. Widgets that need levels scale this one rather than asking for
  /// five more roles.
  final TextStyle heading;

  const TypographyRoles({
    required this.body,
    required this.blockText,
    required this.small,
    required this.mono,
    required this.heading,
  });

  /// A floor, not a look: the platform's own faces at plain sizes.
  static const TypographyRoles fallback = TypographyRoles(
    body: TextStyle(fontSize: 14, height: 1.4),
    blockText: TextStyle(fontSize: 16, height: 1.6),
    small: TextStyle(fontSize: 12, height: 1.35),
    mono: TextStyle(
      fontSize: 13,
      height: 1.5,
      fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'],
    ),
    heading: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600),
  );

  TypographyRoles copyWith({
    TextStyle? body,
    TextStyle? blockText,
    TextStyle? small,
    TextStyle? mono,
    TextStyle? heading,
  }) {
    return TypographyRoles(
      body: body ?? this.body,
      blockText: blockText ?? this.blockText,
      small: small ?? this.small,
      mono: mono ?? this.mono,
      heading: heading ?? this.heading,
    );
  }

  /// Every role at [factor] times its size. A style that never named a size
  /// keeps not naming one — scaling nothing is the honest answer there.
  TypographyRoles scaled(double factor) {
    if (factor == 1.0) {
      return this;
    }

    return TypographyRoles(
      body: body.apply(fontSizeFactor: factor),
      blockText: blockText.apply(fontSizeFactor: factor),
      small: small.apply(fontSizeFactor: factor),
      mono: mono.apply(fontSizeFactor: factor),
      heading: heading.apply(fontSizeFactor: factor),
    );
  }

  static TypographyRoles lerp(TypographyRoles a, TypographyRoles b, double t) {
    return TypographyRoles(
      body: TextStyle.lerp(a.body, b.body, t)!,
      blockText: TextStyle.lerp(a.blockText, b.blockText, t)!,
      small: TextStyle.lerp(a.small, b.small, t)!,
      mono: TextStyle.lerp(a.mono, b.mono, t)!,
      heading: TextStyle.lerp(a.heading, b.heading, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is TypographyRoles &&
        other.body == body &&
        other.blockText == blockText &&
        other.small == small &&
        other.mono == mono &&
        other.heading == heading;
  }

  @override
  int get hashCode => Object.hash(body, blockText, small, mono, heading);
}
