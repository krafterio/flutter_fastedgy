/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../container/container.dart';
import '../ui/icons.dart';
import '../ui/theme/theme.dart';

/// What an image shows while it loads, and when it cannot be read: drawn with
/// the roles of the [FastEdgyTheme] in scope, so that a dark theme gets dark
/// placeholders, and with its glyph for a picture that could not be read.
class ImagePlaceholders {
  const ImagePlaceholders();

  static ImagePlaceholders get registered => hasService<ImagePlaceholders>()
      ? getService<ImagePlaceholders>()
      : const ImagePlaceholders();

  Widget loading(BuildContext context, {double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: FastEdgyTheme.of(context).colors.ink.withValues(alpha: 0.12),
    );
  }

  Widget error(BuildContext context, {double? width, double? height}) {
    final colors = FastEdgyTheme.of(context).colors;

    return Container(
      width: width,
      height: height,
      color: colors.subtleSurface,
      child: Icon(
        FastEdgyIcons.of(context)[FastEdgyGlyph.imageMissing],
        color: colors.muted,
      ),
    );
  }
}
