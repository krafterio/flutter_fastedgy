/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';

/// Persistent blob store for storage images, keyed by storage path then
/// variant key (see `ImageVariant.key`).
///
/// This is the disk layer of the image pipeline: the in-memory `ImageCache`
/// stays the fast path, this store keeps the blobs across restarts so images
/// remain displayable offline.
abstract class LocalImageStore {
  /// Open the underlying database (idempotent).
  Future<void> open();

  /// Close the underlying database.
  Future<void> close();

  /// Get a variant's bytes, or null when absent.
  Future<Uint8List?> getVariant(String path, String variantKey);

  /// Whether a variant is stored.
  Future<bool> hasVariant(String path, String variantKey);

  /// Get the most faithful stored variant of [path] (the original when
  /// present, else the largest rendition), or null when none.
  Future<Uint8List?> getBestVariant(String path);

  /// Store a variant's bytes ([width]/[height] describe the rendition and
  /// drive [getBestVariant]; null means original/unbounded).
  Future<void> putVariant(
    String path,
    String variantKey,
    Uint8List bytes, {
    int? width,
    int? height,
  });

  /// Remove every stored variant of [path].
  Future<void> removePath(String path);

  /// All paths currently holding at least one variant.
  Future<List<String>> paths();

  /// Remove everything (e.g. on logout).
  Future<void> clear();
}
