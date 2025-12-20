/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
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
          ? ImageDimensionsHelper.calculatePhysicalDimension(context, configurationSize.width)
          : null;
      final inferredHeight = configurationSize.height.isFinite
          ? ImageDimensionsHelper.calculatePhysicalDimension(context, configurationSize.height)
          : null;
      return (inferredWidth, inferredHeight);
    }

    return (null, null);
  }

  String _getCacheKey({Size? configurationSize}) {
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions(configurationSize: configurationSize);
    final widthStr = physicalWidth?.toString() ?? 'auto';
    final heightStr = physicalHeight?.toString() ?? 'auto';
    final fmt = format ?? 'webp';
    return '$path|${widthStr}x$heightStr|$mode|$fmt';
  }

  String _buildUrl({Size? configurationSize}) {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
    final url = '$apiBaseUrl/storage/download/$path';

    final params = <String, String>{};
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions(configurationSize: configurationSize);

    if (physicalWidth != null) {
      params['w'] = physicalWidth.toString();
    }
    if (physicalHeight != null) {
      params['h'] = physicalHeight.toString();
    }
    params['m'] = mode;
    if (format != null) {
      params['e'] = format!;
    }

    if (params.isEmpty) {
      return url;
    }

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$url?$queryString';
  }

  @override
  Future<CachedApiImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedApiImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(CachedApiImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, null),
      scale: 1.0,
    );
  }

  @override
  ImageStreamCompleter loadBuffer(CachedApiImageProvider key, DecoderBufferCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, null, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedApiImageProvider key,
    ImageDecoderCallback? legacyDecode,
    DecoderBufferCallback? decode,
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
      if (decode != null) {
        return decode(buffer);
      } else if (legacyDecode != null) {
        return legacyDecode(buffer);
      }
    }

    // Check pending request
    final pendingRequest = imageCache.getPendingRequest(cacheKey);
    if (pendingRequest != null) {
      final bytes = await pendingRequest;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      if (decode != null) {
        return decode(buffer);
      } else if (legacyDecode != null) {
        return legacyDecode(buffer);
      }
    }

    // Start new request
    final fetcher = getService<Fetcher>();
    final url = _buildUrl(configurationSize: configurationSize);

    final logger = getLogger('CachedApiImageProvider');
    logger.finer('Loading image from $url');

    final future = fetcher
        .get(url, responseType: ResponseType.bytes)
        .then((response) {
      return Uint8List.fromList(response.data as List<int>);
    });

    imageCache.setPendingRequest(cacheKey, future);

    final bytes = await future;
    imageCache.cacheImage(cacheKey, bytes);

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);

    // Use the appropriate decode callback
    if (decode != null) {
      return decode(buffer);
    } else if (legacyDecode != null) {
      return legacyDecode(buffer);
    } else {
      throw StateError('No decode callback provided');
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
        other.autoCalculatePhysicalDimensions == autoCalculatePhysicalDimensions;
  }

  @override
  int get hashCode => Object.hash(path, width, height, mode, format, autoCalculatePhysicalDimensions);
}
