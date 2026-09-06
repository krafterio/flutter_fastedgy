/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

/// Helper class for calculating physical image dimensions based on device pixel ratio
///
/// This ensures images are downloaded at the optimal resolution for the device:
/// - iPhone Retina (3x): logical 100px → physical 300px
/// - Android HD (2x): logical 100px → physical 200px
/// - Standard (1x): logical 100px → physical 100px
///
/// Example:
/// ```dart
/// // Calculate single dimension
/// final physical = ImageDimensionsHelper.calculatePhysicalDimension(context, 100.0);
///
/// // Calculate both dimensions
/// final (width, height) = ImageDimensionsHelper.calculatePhysicalDimensions(
///   context,
///   width: 200,
///   height: 150,
/// );
/// ```
class ImageDimensionsHelper {
  /// Calculate physical dimension from logical size
  ///
  /// Returns null if logicalSize is null or infinite.
  ///
  /// Example:
  /// ```dart
  /// // On iPhone Retina (3x)
  /// final physical = ImageDimensionsHelper.calculatePhysicalDimension(context, 100.0);
  /// print(physical); // 300
  /// ```
  static int? calculatePhysicalDimension(
    BuildContext context,
    double? logicalSize,
  ) {
    if (logicalSize == null || !logicalSize.isFinite) return null;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    return (logicalSize * devicePixelRatio).round();
  }

  /// Calculate both width and height physical dimensions
  ///
  /// Returns a record (width, height) with physical dimensions.
  ///
  /// Example:
  /// ```dart
  /// final (physicalWidth, physicalHeight) = ImageDimensionsHelper.calculatePhysicalDimensions(
  ///   context,
  ///   width: 200,
  ///   height: 150,
  /// );
  /// ```
  static (int?, int?) calculatePhysicalDimensions(
    BuildContext context, {
    double? width,
    double? height,
  }) {
    final physicalWidth = calculatePhysicalDimension(context, width);
    final physicalHeight = calculatePhysicalDimension(context, height);
    return (physicalWidth, physicalHeight);
  }

  /// Step, in physical pixels, an inferred dimension is rounded up to.
  static const int inferredDimensionStep = 64;

  /// Physical dimension for a size read off the layout, rounded up to
  /// [inferredDimensionStep].
  ///
  /// A widget sized by its parent is measured again at every frame of a resize
  /// animation, and each distinct value is another rendition to download and
  /// another variant for the server to encode from the original file. Rounding
  /// up collapses a whole animation onto one or two renditions, and gives
  /// devices of different pixel ratios a chance to share them.
  static int? inferPhysicalDimension(
    BuildContext context,
    double? logicalSize,
  ) {
    final physical = calculatePhysicalDimension(context, logicalSize);

    if (physical == null || physical <= 0) return physical;

    const step = inferredDimensionStep;

    return ((physical + step - 1) ~/ step) * step;
  }

  /// Infer dimension from BoxConstraints
  ///
  /// Useful when you want to fill available space.
  ///
  /// Example:
  /// ```dart
  /// LayoutBuilder(
  ///   builder: (context, constraints) {
  ///     final physicalWidth = ImageDimensionsHelper.inferDimensionFromConstraints(
  ///       context,
  ///       constraints,
  ///       Axis.horizontal,
  ///     );
  ///     return CachedApiImage(path: '...', width: physicalWidth);
  ///   },
  /// )
  /// ```
  static int? inferDimensionFromConstraints(
    BuildContext context,
    BoxConstraints? constraints,
    Axis axis,
  ) {
    if (constraints == null) return null;

    final maxSize = axis == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;

    if (!maxSize.isFinite) return null;

    return inferPhysicalDimension(context, maxSize);
  }
}
