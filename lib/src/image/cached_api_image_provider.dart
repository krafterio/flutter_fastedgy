/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../container/container.dart';
import '../storage/storage_downloader.dart';
import '../logging/logger.dart';
import 'image_cache.dart' as fastedgy_cache;
import 'storage_image_bytes.dart';
import 'image_dimensions_helper.dart';

/// ImageProvider for cached API images
///
/// Use this with widgets that require an ImageProvider, such as CircleAvatar:
/// ```dart
/// CircleAvatar(
///   backgroundImage: CachedApiImageProvider(
///     context: context,
///     path: 'users/123/avatar.jpg',
///     width: 64,
///     height: 64,
///   ),
/// )
/// ```
///
/// For most cases, prefer using CachedApiImage widget directly.
class CachedApiImageProvider extends ImageProvider<CachedApiImageProvider> {
  final BuildContext context;
  final String path;
  final double? width;
  final double? height;
  final String mode;
  final String? format;
  final bool autoCalculatePhysicalDimensions;

  const CachedApiImageProvider({
    required this.context,
    required this.path,
    this.width,
    this.height,
    this.mode = 'cover',
    this.format = 'webp',
    this.autoCalculatePhysicalDimensions = true,
  });

  (int?, int?) _getPhysicalDimensions({Size? configurationSize}) {
    if (!autoCalculatePhysicalDimensions) {
      return (width?.toInt(), height?.toInt());
    }

    // If explicit dimensions are provided, use them
    if (width != null || height != null) {
      return ImageDimensionsHelper.calculatePhysicalDimensions(
        context,
        width: width,
        height: height,
      );
    }

    // Otherwise, try to infer from ImageConfiguration.size
    if (configurationSize != null) {
      final inferredWidth = configurationSize.width.isFinite
          ? ImageDimensionsHelper.calculatePhysicalDimension(
              context,
              configurationSize.width,
            )
          : null;
      final inferredHeight = configurationSize.height.isFinite
          ? ImageDimensionsHelper.calculatePhysicalDimension(
              context,
              configurationSize.height,
            )
          : null;
      return (inferredWidth, inferredHeight);
    }

    return (null, null);
  }

  String _getCacheKey({Size? configurationSize}) {
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions(
      configurationSize: configurationSize,
    );
    final widthStr = physicalWidth?.toString() ?? 'auto';
    final heightStr = physicalHeight?.toString() ?? 'auto';
    final fmt = format ?? 'webp';
    return '$path|${widthStr}x$heightStr|$mode|$fmt';
  }

  @override
  Future<CachedApiImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedApiImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedApiImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedApiImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    // Try to get size from the key's context if available
    Size? configurationSize;
    try {
      final renderObject = key.context.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        configurationSize = renderObject.size;
      }
    } catch (_) {
      // Context might not be available or mounted
    }

    final cacheKey = _getCacheKey(configurationSize: configurationSize);
    final imageCache = getService<fastedgy_cache.ImageCache>();

    // Check cache
    final cachedImage = imageCache.getCachedImage(cacheKey);
    if (cachedImage != null) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(cachedImage);
      return decode(buffer);
    }

    // Check pending request
    final pendingRequest = imageCache.getPendingRequest(cacheKey);
    if (pendingRequest != null) {
      final bytes = await pendingRequest;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    }

    // Start new request
    final downloader = getService<StorageDownloader>();
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions(
      configurationSize: configurationSize,
    );

    final logger = getLogger('CachedApiImageProvider');
    logger.finer(
      'Loading image from path: $path with dimensions: ${physicalWidth}x$physicalHeight',
    );

    final future = _fetchBytes(
      downloader,
      physicalWidth: physicalWidth,
      physicalHeight: physicalHeight,
    );

    imageCache.setPendingRequest(cacheKey, future);

    final bytes = await future;
    imageCache.cacheImage(cacheKey, bytes);

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<Uint8List> _fetchBytes(
    StorageDownloader downloader, {
    int? physicalWidth,
    int? physicalHeight,
  }) => fetchStorageImageBytes(
    downloader,
    path: path,
    width: physicalWidth,
    height: physicalHeight,
    mode: mode,
    format: format,
  );

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is CachedApiImageProvider &&
        other.path == path &&
        other.width == width &&
        other.height == height &&
        other.mode == mode &&
        other.format == format &&
        other.autoCalculatePhysicalDimensions ==
            autoCalculatePhysicalDimensions;
  }

  @override
  int get hashCode => Object.hash(
    path,
    width,
    height,
    mode,
    format,
    autoCalculatePhysicalDimensions,
  );
}
