/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:material_ui/material_ui.dart';

import '../container/container.dart';

class ImagePlaceholders {
  const ImagePlaceholders();

  static ImagePlaceholders get registered => hasService<ImagePlaceholders>()
      ? getService<ImagePlaceholders>()
      : const ImagePlaceholders();

  Widget loading(BuildContext context, {double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
    );
  }

  Widget error(BuildContext context, {double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
