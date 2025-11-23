/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
import '../logging/logger.dart';
import 'image_cache.dart' as fastedgy_cache;

/// Image resize mode for API requests
enum ImageMode {
  /// Crop to exact dimensions (default)
  cover('cover'),

  /// Fit within dimensions (maintain aspect ratio)
  contain('contain');

  final String value;
  const ImageMode(this.value);

  @override
  String toString() => value;
}

/// Widget for displaying cached images from API
///
/// Downloads and caches images from the FastEdgy storage API.
/// Supports image optimization with width, height, mode, and format parameters.
///
/// Example:
/// ```dart
/// CachedApiImage(
///   path: 'users/123/avatar.jpg',
///   width: 100,
///   height: 100,
///   mode: ImageMode.cover,
///   format: 'webp',
///   fit: BoxFit.cover,
///   placeholder: Icon(Icons.person, size: 48),
///   fadeInDuration: Duration(milliseconds: 300),
/// )
/// ```
class CachedApiImage extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageMode mode;
  final String? format;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;
  final Widget? placeholder;
  final Duration fadeInDuration;
  final AlignmentGeometry alignment;
  final Color? color;
  final BlendMode? colorBlendMode;

  const CachedApiImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit,
    this.mode = ImageMode.cover,
    this.format = 'webp',
    this.errorBuilder,
    this.loadingBuilder,
    this.placeholder,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode,
  });

  @override
  State<CachedApiImage> createState() => _CachedApiImageState();
}

class _CachedApiImageState extends State<CachedApiImage> {
  final _logger = getLogger('CachedApiImage');

  Uint8List? _imageBytes;
  bool _isLoading = false;
  Object? _error;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        _loadImage();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void didUpdateWidget(CachedApiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.mode != widget.mode ||
        oldWidget.format != widget.format) {
      setState(() {
        _isLoading = false;
        _error = null;
        _imageBytes = null;
      });
      _loadImage();
    }
  }

  String _getCacheKey() {
    final widthStr = widget.width?.toInt().toString() ?? 'auto';
    final heightStr = widget.height?.toInt().toString() ?? 'auto';
    final format = widget.format ?? 'webp';
    return '${widget.path}|${widthStr}x${heightStr}|${widget.mode.value}|$format';
  }

  String _buildUrl() {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? '';
    final url = '$apiBaseUrl/storage/download/${widget.path}';

    final params = <String, String>{};
    if (widget.width != null && widget.width!.isFinite) {
      params['width'] = widget.width!.toInt().toString();
    }
    if (widget.height != null && widget.height!.isFinite) {
      params['height'] = widget.height!.toInt().toString();
    }
    params['mode'] = widget.mode.value;
    if (widget.format != null) {
      params['format'] = widget.format!;
    }

    if (params.isEmpty) {
      return url;
    }

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$url?$queryString';
  }

  Future<void> _loadImage() async {
    if (!mounted || _isDisposed) return;

    final cacheKey = _getCacheKey();
    final imageCache = getService<fastedgy_cache.ImageCache>();

    // Check cache
    final cachedImage = imageCache.getCachedImage(cacheKey);
    if (cachedImage != null) {
      if (mounted) {
        setState(() {
          _imageBytes = cachedImage;
          _isLoading = false;
        });
      }
      return;
    }

    // Check pending request
    final pendingRequest = imageCache.getPendingRequest(cacheKey);
    if (pendingRequest != null) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      try {
        final bytes = await pendingRequest;
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            _isLoading = false;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _error = error;
            _isLoading = false;
          });
        }
      }
      return;
    }

    // Start new request
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (!mounted || _isDisposed) return;

      final fetcher = getService<Fetcher>();
      final url = _buildUrl();

      _logger.finer('Loading image from $url');

      final future = fetcher
          .get(url, responseType: ResponseType.bytes)
          .then((response) {
        return Uint8List.fromList(response.data as List<int>);
      });

      imageCache.setPendingRequest(cacheKey, future);

      final bytes = await future;

      if (mounted) {
        imageCache.cacheImage(cacheKey, bytes);

        setState(() {
          _imageBytes = bytes;
          _isLoading = false;
        });

        _logger.finer('Image loaded successfully');
      }
    } catch (error, stackTrace) {
      _logger.warning('Failed to load image from ${widget.path}', error, stackTrace);
      if (mounted) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      if (widget.loadingBuilder != null) {
        return widget.loadingBuilder!(context);
      }
      if (widget.placeholder != null) {
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.placeholder,
        );
      }
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, StackTrace.empty);
      }
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    if (_imageBytes == null) {
      return const SizedBox.shrink();
    }

    final image = Image.memory(
      _imageBytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );

    // Fade-in animation
    return AnimatedSwitcher(
      duration: widget.fadeInDuration,
      child: image,
    );
  }
}
