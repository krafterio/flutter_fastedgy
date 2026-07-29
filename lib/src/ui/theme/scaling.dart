/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'theme_data.dart';

/// Desktop and mobile draw the *same* components at different scales. A scale
/// says so; two token sets would say they are different products.
@immutable
class AdaptiveScaling {
  final double radiusScaling;
  final double sizeScaling;
  final double textScaling;

  const AdaptiveScaling({
    this.radiusScaling = 1.0,
    this.sizeScaling = 1.0,
    this.textScaling = 1.0,
  });

  const AdaptiveScaling.all(double scale)
    : radiusScaling = scale,
      sizeScaling = scale,
      textScaling = scale;

  static const AdaptiveScaling desktop = AdaptiveScaling();

  static const AdaptiveScaling mobile = AdaptiveScaling.all(1.25);

  /// [theme] at this scale, whatever scale it is already at.
  ///
  /// Relative rather than absolute, which is what makes it safe: applying a
  /// scale twice changes nothing, and going back to [desktop] returns the
  /// theme that was authored. A widget can therefore rescale a subtree without
  /// knowing what the shell did above it.
  FastEdgyThemeData scale(FastEdgyThemeData theme) {
    final current = theme.scaling;

    if (current == this) {
      return theme;
    }

    return theme.copyWith(
      radius: theme.radius * (radiusScaling / current.radiusScaling),
      spacing: theme.spacing * (sizeScaling / current.sizeScaling),
      typography: theme.typography.scaled(textScaling / current.textScaling),
      scaling: this,
    );
  }

  AdaptiveScaling copyWith({
    double? radiusScaling,
    double? sizeScaling,
    double? textScaling,
  }) {
    return AdaptiveScaling(
      radiusScaling: radiusScaling ?? this.radiusScaling,
      sizeScaling: sizeScaling ?? this.sizeScaling,
      textScaling: textScaling ?? this.textScaling,
    );
  }

  static AdaptiveScaling lerp(AdaptiveScaling a, AdaptiveScaling b, double t) {
    return AdaptiveScaling(
      radiusScaling: lerpDouble(a.radiusScaling, b.radiusScaling, t)!,
      sizeScaling: lerpDouble(a.sizeScaling, b.sizeScaling, t)!,
      textScaling: lerpDouble(a.textScaling, b.textScaling, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is AdaptiveScaling &&
        other.radiusScaling == radiusScaling &&
        other.sizeScaling == sizeScaling &&
        other.textScaling == textScaling;
  }

  @override
  int get hashCode => Object.hash(radiusScaling, sizeScaling, textScaling);
}

/// The second axis: the same theme drawn tight or loose — a table against a
/// reading surface — without changing a single colour, corner or face.
///
/// Air only, on purpose. Shrinking the type or the corners to fit more rows
/// would make a dense table a different design rather than the same one drawn
/// closer together.
enum Density {
  compact(0.8),
  standard(1.0),
  comfortable(1.2);

  final double factor;

  const Density(this.factor);

  /// [theme] at this density, whatever density it is already at — relative for
  /// the same reason [AdaptiveScaling.scale] is, and commutative with it.
  FastEdgyThemeData apply(FastEdgyThemeData theme) {
    final current = theme.density;

    if (current == this) {
      return theme;
    }

    return theme.copyWith(
      spacing: theme.spacing * (factor / current.factor),
      density: this,
    );
  }
}
