/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

/// One choice among several: of a picker, of a field of a record form.
class ComboOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  /// Drawn before the label: an avatar, a colour.
  final Widget? image;

  /// Drawn before the label without an [image]: an emoji, or else an icon in
  /// [color].
  final String? emoji;
  final IconData? icon;
  final Color? color;

  /// Draws the icon of the option in the ink it takes, chosen or not, in
  /// place of [icon].
  final Widget Function(Color ink)? iconBuilder;

  const ComboOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.image,
    this.emoji,
    this.icon,
    this.color,
    this.iconBuilder,
  });
}
