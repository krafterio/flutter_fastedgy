/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:image/image.dart' as img;

/// Result of a storage upload operation
class StorageUploadResult {
  /// The storage path of the uploaded file
  final String path;

  const StorageUploadResult({
    required this.path,
  });

  factory StorageUploadResult.fromJson(Map<String, dynamic> json) {
    return StorageUploadResult(
      path: json['path'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
    };
  }

  @override
  String toString() => 'StorageUploadResult(path: $path)';
}

/// Image format for compression
enum ImageFormat {
  jpeg('jpeg'),
  png('png'),
  webp('webp');

  final String value;
  const ImageFormat(this.value);

  @override
  String toString() => value;

  /// Get image format from file extension
  static ImageFormat? fromExtension(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return ImageFormat.jpeg;
      case 'png':
        return ImageFormat.png;
      case 'webp':
        return ImageFormat.webp;
      default:
        return null;
    }
  }

  /// Get MIME type for this format
  String get mimeType {
    switch (this) {
      case ImageFormat.jpeg:
        return 'image/jpeg';
      case ImageFormat.png:
        return 'image/png';
      case ImageFormat.webp:
        return 'image/webp';
    }
  }

  /// Encode image to bytes
  List<int> encode(img.Image image, {int quality = 85}) {
    switch (this) {
      case ImageFormat.jpeg:
        return img.encodeJpg(image, quality: quality);
      case ImageFormat.png:
        return img.encodePng(image);
      case ImageFormat.webp:
        // WebP encoding not available in image package, fallback to JPEG
        return img.encodeJpg(image, quality: quality);
    }
  }
}

/// Options for image compression before upload
class CompressionOptions {
  /// Quality (0-100), default 85
  final int quality;

  /// Maximum size in bytes (optional)
  final int? maxSizeBytes;

  /// Target format (default: JPEG)
  final ImageFormat format;

  /// Maximum width (optional)
  final int? maxWidth;

  /// Maximum height (optional)
  final int? maxHeight;

  const CompressionOptions({
    this.quality = 85,
    this.maxSizeBytes,
    this.format = ImageFormat.jpeg,
    this.maxWidth,
    this.maxHeight,
  });

  @override
  String toString() {
    return 'CompressionOptions('
        'quality: $quality, '
        'maxSizeBytes: $maxSizeBytes, '
        'format: $format, '
        'maxWidth: $maxWidth, '
        'maxHeight: $maxHeight'
        ')';
  }
}
