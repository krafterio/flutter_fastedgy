/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// A server-side processed rendition of a storage image (resize + format,
/// matching the `w`/`h`/`m`/`e` params of the storage download endpoint).
///
/// A variant with no width, height and a null [format] downloads the original
/// file untouched.
class ImageVariant {
  final int? width;
  final int? height;

  /// Resize mode: 'cover' or 'contain'.
  final String mode;

  /// Output format ('webp', 'jpeg', 'png'); null keeps the original format.
  final String? format;

  const ImageVariant({
    this.width,
    this.height,
    this.mode = 'cover',
    this.format = 'webp',
  });

  /// The original file, unprocessed.
  const ImageVariant.original()
    : width = null,
      height = null,
      mode = 'cover',
      format = null;

  /// Whether the server should process the image at all.
  bool get isProcessed => width != null || height != null || format != null;

  /// Storage key of this variant inside its path namespace — aligned with the
  /// in-memory cache key of CachedApiImageProvider (`WxH|mode|fmt`).
  String get key =>
      '${width ?? 'auto'}x${height ?? 'auto'}|$mode|${format ?? 'original'}';

  @override
  bool operator ==(Object other) => other is ImageVariant && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Declares an image field of a synced model to mirror into the offline image
/// store, with the renditions worth prefetching.
///
/// The field must be part of the sync selection (`syncFields`) so its storage
/// path is present on the cached records.
///
/// ```dart
/// @override
/// List<SyncImageField> get syncImageFields => const [
///   SyncImageField('avatar', variants: [ImageVariant(width: 128, height: 128)]),
/// ];
/// ```
class SyncImageField {
  final String field;

  /// Renditions to prefetch; empty downloads the original file.
  final List<ImageVariant> variants;

  const SyncImageField(this.field, {this.variants = const []});

  /// The variants to mirror ([ImageVariant.original] when none declared).
  List<ImageVariant> get effectiveVariants =>
      variants.isEmpty ? const [ImageVariant.original()] : variants;
}
