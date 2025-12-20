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

  (int?, int?) _getPhysicalDimensions() {
    if (!autoCalculatePhysicalDimensions) {
      return (width?.toInt(), height?.toInt());
    }

    return ImageDimensionsHelper.calculatePhysicalDimensions(
      context,
      width: width,
      height: height,
    );
  }

  String _getCacheKey() {
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions();
    final widthStr = physicalWidth?.toString() ?? 'auto';
    final heightStr = physicalHeight?.toString() ?? 'auto';
    final fmt = format ?? 'webp';
    return '$path|${widthStr}x$heightStr|$mode|$fmt';
  }

  String _buildUrl() {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
    final url = '$apiBaseUrl/storage/download/$path';

    final params = <String, String>{};
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions();

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
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(CachedApiImageProvider key, ImageDecoderCallback decode) async {
    final cacheKey = _getCacheKey();
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
    final fetcher = getService<Fetcher>();
    final url = _buildUrl();

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
    return decode(buffer);
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
