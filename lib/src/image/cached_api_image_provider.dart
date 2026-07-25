/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../container/container.dart';
import '../offline/local_image_store.dart';
import '../offline/offline_error.dart';
import '../offline/pending_upload_store.dart';
import '../storage/storage_downloader.dart';
import '../logging/logger.dart';
import 'image_cache.dart' as fastedgy_cache;
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

  // Network fetch with persistence in the offline image store (when
  // registered) and disk fallback on connectivity failure: the exact stored
  // variant first, else the most faithful one available for the path.
  Future<Uint8List> _fetchBytes(
    StorageDownloader downloader, {
    int? physicalWidth,
    int? physicalHeight,
  }) async {
    final imageStore = hasService<LocalImageStore>()
        ? getService<LocalImageStore>()
        : null;
    final variantKey =
        '${physicalWidth ?? 'auto'}x${physicalHeight ?? 'auto'}|$mode|${format ?? 'webp'}';

    // A file still waiting for its upload exists only locally: the server knows
    // no such path, so asking it would fail with a status the offline fallback
    // below does not cover — the image would stay blank while connected.
    if (pendingUploadIdOf(path) != null) {
      final pending = await imageStore?.getBestVariant(path);

      if (pending == null) {
        throw StateError('No local bytes for the pending upload "$path"');
      }

      return pending;
    }

    try {
      final bytes = await downloader.downloadPath(
        path,
        width: physicalWidth,
        height: physicalHeight,
        resizeMode: mode,
        outputFormat: format,
      );

      await imageStore?.putVariant(
        path,
        variantKey,
        bytes,
        width: physicalWidth,
        height: physicalHeight,
      );

      return bytes;
    } catch (error) {
      if (imageStore == null || !isServerUnavailable(error)) {
        rethrow;
      }

      final stored =
          await imageStore.getVariant(path, variantKey) ??
          await imageStore.getBestVariant(path);

      if (stored == null) {
        rethrow;
      }

      return stored;
    }
  }

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
