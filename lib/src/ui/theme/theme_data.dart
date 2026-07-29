/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'color_scheme.dart';
import 'component_theme.dart';
import 'scaling.dart';
import 'typography.dart';

/// Everything a package needs to draw itself, and nothing a product is
/// recognised by. What each role *looks like* is supplied by whoever mounts a
/// [FastEdgyTheme]; the framework only says what the roles are.
///
/// Light and dark are two whole instances of this, not a pair of values per
/// role: a read costs one lookup instead of a branch, and no `…Static` escape
/// hatch is ever needed for a place that has no context.
@immutable
class FastEdgyThemeData {
  final ColorRoles colors;
  final TypographyRoles typography;

  /// The corner a rounded shape takes, before [AdaptiveScaling.radiusScaling].
  final double radius;

  /// The base unit gaps and padding are taken as multiples of.
  final double spacing;

  final AdaptiveScaling scaling;
  final Density density;

  /// What each package that draws something is drawn with, keyed by its type.
  ///
  /// Here rather than one inherited widget per theme: an application supplies
  /// its whole design in the same breath as its tokens, instead of nesting a
  /// `ComponentTheme` per package and finding out it forgot one when something
  /// comes out plain. `ComponentTheme<T>` stays for what it is actually for —
  /// a subtree that wants its own.
  final Map<Type, ComponentThemeData> components;

  const FastEdgyThemeData({
    this.colors = ColorRoles.fallback,
    this.typography = TypographyRoles.fallback,
    this.radius = 6.0,
    this.spacing = 4.0,
    this.scaling = AdaptiveScaling.desktop,
    this.density = Density.standard,
    this.components = const {},
  });

  /// The theme declared for [T], or null where the application declared none.
  T? component<T extends ComponentThemeData>() => components[T] as T?;

  /// A floor, not a look. Every role resolves to something legible with nothing
  /// supplied, so a package is usable on day one — and it is deliberately
  /// unremarkable, so nobody ships it by accident.
  static const FastEdgyThemeData fallback = FastEdgyThemeData();

  FastEdgyThemeData copyWith({
    ColorRoles? colors,
    TypographyRoles? typography,
    double? radius,
    double? spacing,
    AdaptiveScaling? scaling,
    Density? density,
    Map<Type, ComponentThemeData>? components,
  }) {
    return FastEdgyThemeData(
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      radius: radius ?? this.radius,
      spacing: spacing ?? this.spacing,
      scaling: scaling ?? this.scaling,
      density: density ?? this.density,
      components: components ?? this.components,
    );
  }

  static FastEdgyThemeData lerp(
    FastEdgyThemeData a,
    FastEdgyThemeData b,
    double t,
  ) {
    return FastEdgyThemeData(
      colors: ColorRoles.lerp(a.colors, b.colors, t),
      typography: TypographyRoles.lerp(a.typography, b.typography, t),
      radius: lerpDouble(a.radius, b.radius, t)!,
      spacing: lerpDouble(a.spacing, b.spacing, t)!,
      scaling: AdaptiveScaling.lerp(a.scaling, b.scaling, t),
      // Discrete: an interpolated density would be a fourth value nobody named.
      density: t < 0.5 ? a.density : b.density,
      // Discrete too: a package theme knows how to interpolate itself or does
      // not, and the engine cannot know which.
      components: t < 0.5 ? a.components : b.components,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is FastEdgyThemeData &&
        other.colors == colors &&
        other.typography == typography &&
        other.radius == radius &&
        other.spacing == spacing &&
        other.scaling == scaling &&
        other.density == density &&
        other.components.length == components.length &&
        other.components.entries.every((e) => components[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hash(
    colors,
    typography,
    radius,
    spacing,
    scaling,
    density,
    components.length,
  );
}
