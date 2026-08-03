/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../container/container.dart';
import '../storage/storage_downloader.dart';
import '../logging/logger.dart';
import 'image_cache.dart' as fastedgy_cache;
import 'storage_image_bytes.dart';
import 'image_dimensions_helper.dart';

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
/// The widget automatically applies the correct BoxFit based on the mode:
/// - ImageMode.cover → BoxFit.cover (fills container, may crop)
/// - ImageMode.contain → BoxFit.contain (fits inside container, may letterbox)
///
/// By default, automatically calculates physical dimensions based on device pixel ratio:
/// - iPhone Retina (3x): width 100 → downloads 300px
/// - Android HD (2x): width 100 → downloads 200px
/// - Standard (1x): width 100 → downloads 100px
///
/// Example:
/// ```dart
/// CachedApiImage(
///   path: 'users/123/avatar.jpg',
///   width: 100,
///   height: 100,
///   mode: ImageMode.cover, // Automatically uses BoxFit.cover
///   format: 'webp',
///   placeholder: Icon(Icons.person, size: 48),
///   fadeInDuration: Duration(milliseconds: 300),
/// )
/// ```
class CachedApiImage extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final ImageMode mode;
  final String? format;

  /// If true, automatically calculates physical dimensions based on devicePixelRatio
  /// This ensures optimal image quality for each device (Retina, HD, etc.)
  /// Default: true
  final bool autoCalculatePhysicalDimensions;

  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;
  final Widget? placeholder;
  final Duration fadeInDuration;
  final AlignmentGeometry alignment;
  final Color? color;
  final BlendMode? colorBlendMode;

  const CachedApiImage({
    required this.path,
    super.key,
    this.width,
    this.height,
    this.mode = ImageMode.cover,
    this.format = 'webp',
    this.autoCalculatePhysicalDimensions = true,
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
  BoxConstraints? _lastConstraints;
  bool _probedCache = false;

  @override
  void initState() {
    super.initState();
    // Only load immediately if explicit dimensions are provided
    // Otherwise, wait for LayoutBuilder in build() to provide constraints
    if (widget.width != null || widget.height != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          _loadImage();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // What is already in memory, taken before the first frame is drawn.
    //
    // Loading is otherwise asked for after that frame, so a widget rebuilt from
    // scratch over an image the cache already holds still painted its loading
    // state once — a picture that blinks every time the list around it is
    // rebuilt, which is every time a block is added above it. Reading the cache
    // here costs a map lookup and skips the blink; the frame after still asks,
    // and still finds the same bytes.
    //
    // Here rather than in initState: the key is computed from the device pixel
    // ratio, which is an inherited value and not one to read before this.
    if (_probedCache || (widget.width == null && widget.height == null)) {
      return;
    }

    _probedCache = true;
    _imageBytes = getService<fastedgy_cache.ImageCache>().getCachedImage(
      _getCacheKey(),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  (int?, int?) _getPhysicalDimensions({BoxConstraints? constraints}) {
    if (!widget.autoCalculatePhysicalDimensions || !mounted) {
      return (widget.width?.toInt(), widget.height?.toInt());
    }

    // If explicit dimensions are provided, use them
    if (widget.width != null || widget.height != null) {
      return ImageDimensionsHelper.calculatePhysicalDimensions(
        context,
        width: widget.width,
        height: widget.height,
      );
    }

    // Otherwise, try to infer from constraints
    if (constraints != null) {
      final inferredWidth = ImageDimensionsHelper.inferDimensionFromConstraints(
        context,
        constraints,
        Axis.horizontal,
      );
      final inferredHeight =
          ImageDimensionsHelper.inferDimensionFromConstraints(
            context,
            constraints,
            Axis.vertical,
          );
      return (inferredWidth, inferredHeight);
    }

    return (null, null);
  }

  @override
  void didUpdateWidget(CachedApiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.mode != widget.mode ||
        oldWidget.format != widget.format ||
        oldWidget.autoCalculatePhysicalDimensions !=
            widget.autoCalculatePhysicalDimensions) {
      setState(() {
        _isLoading = false;
        _error = null;
        _imageBytes = null;
      });
      _loadImage();
    }
  }

  String _getCacheKey({BoxConstraints? constraints}) {
    final (physicalWidth, physicalHeight) = _getPhysicalDimensions(
      constraints: constraints,
    );
    final widthStr = physicalWidth?.toString() ?? 'auto';
    final heightStr = physicalHeight?.toString() ?? 'auto';
    final format = widget.format ?? 'webp';
    return '${widget.path}|${widthStr}x$heightStr|${widget.mode.value}|$format';
  }

  /// Bytes that are not an image at all: a truncated download, an error page
  /// answered by a proxy. Without this the codec throws where nothing catches
  /// it, and the whole app goes down for a broken thumbnail.
  ///
  /// The entry is dropped from the cache so the next build downloads again
  /// instead of failing forever on the same bytes.
  Widget _onDecodeFailed(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    getService<fastedgy_cache.ImageCache>().clearCache(_getCacheKey());

    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(context, error, stackTrace);
    }

    return SizedBox(width: widget.width, height: widget.height);
  }

  Future<void> _loadImage({BoxConstraints? constraints}) async {
    if (!mounted || _isDisposed) return;

    final cacheKey = _getCacheKey(constraints: constraints);
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

      final downloader = getService<StorageDownloader>();
      final (physicalWidth, physicalHeight) = _getPhysicalDimensions(
        constraints: constraints,
      );

      _logger.finer(
        'Loading image from path: ${widget.path} with dimensions: ${physicalWidth}x$physicalHeight',
      );

      final future = fetchStorageImageBytes(
        downloader,
        path: widget.path,
        width: physicalWidth,
        height: physicalHeight,
        mode: widget.mode.value,
        format: widget.format,
      );

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
    } catch (error) {
      _logger.fine('Failed to load image from ${widget.path}: $error');
      imageCache.removePendingRequest(cacheKey);
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
    // Use LayoutBuilder to detect parent constraints when dimensions are not provided
    return LayoutBuilder(
      builder: (context, constraints) {
        // Load image with constraints if not already loaded or if constraints changed
        if (_imageBytes == null && !_isLoading && _error == null) {
          _lastConstraints = constraints;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isDisposed) {
              _loadImage(constraints: constraints);
            }
          });
        } else if (_lastConstraints != constraints &&
            widget.width == null &&
            widget.height == null) {
          // Reload if constraints changed significantly and no explicit dimensions
          final oldDims = _getPhysicalDimensions(constraints: _lastConstraints);
          final newDims = _getPhysicalDimensions(constraints: constraints);
          _lastConstraints = constraints;

          // Only reload if dimensions actually changed
          if (oldDims != newDims) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isDisposed) {
                setState(() {
                  _imageBytes = null;
                  _error = null;
                });
                _loadImage(constraints: constraints);
              }
            });
          }
        }

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

        // Map ImageMode to BoxFit automatically
        final boxFit = widget.mode == ImageMode.cover
            ? BoxFit.cover
            : BoxFit.contain;

        final image = Image.memory(
          _imageBytes!,
          width: widget.width,
          height: widget.height,
          fit: boxFit,
          alignment: widget.alignment,
          color: widget.color,
          colorBlendMode: widget.colorBlendMode,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: _onDecodeFailed,
        );

        // Fade-in animation
        return AnimatedSwitcher(duration: widget.fadeInDuration, child: image);
      },
    );
  }
}
