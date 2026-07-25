/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../container/container.dart';
import '../offline/local_image_store.dart';
import '../offline/offline_error.dart';
import '../offline/pending_upload_store.dart';
import '../storage/storage_downloader.dart';

/// Variant key a rendition is stored under (mirrors `ImageVariant.key`).
String storageImageVariantKey({
  required String mode,
  int? width,
  int? height,
  String? format,
}) => '${width ?? 'auto'}x${height ?? 'auto'}|$mode|${format ?? 'webp'}';

/// Bytes of a storage image: from the server, from the local mirror when it
/// cannot be reached, or straight from disk for a file awaiting its upload.
///
/// Shared by [CachedApiImage] and [CachedApiImageProvider] so both take the same
/// path — a fallback living in only one of them is a fallback the other lacks.
Future<Uint8List> fetchStorageImageBytes(
  StorageDownloader downloader, {
  required String path,
  required String mode,
  int? width,
  int? height,
  String? format,
}) async {
  final imageStore = hasService<LocalImageStore>()
      ? getService<LocalImageStore>()
      : null;
  final variantKey = storageImageVariantKey(
    width: width,
    height: height,
    mode: mode,
    format: format,
  );

  // A file still waiting for its upload exists only locally: the server knows no
  // such path, and would answer a status the fallback below does not cover.
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
      width: width,
      height: height,
      resizeMode: mode,
      outputFormat: format,
    );

    await imageStore?.putVariant(
      path,
      variantKey,
      bytes,
      width: width,
      height: height,
    );

    return bytes;
  } catch (error) {
    if (imageStore == null || !isServerUnavailable(error)) {
      rethrow;
    }

    // The exact rendition first, else the most faithful one stored: the mirror
    // holds the variants a model declares, not the size a widget asks for.
    final stored =
        await imageStore.getVariant(path, variantKey) ??
        await imageStore.getBestVariant(path);

    if (stored == null) {
      rethrow;
    }

    return stored;
  }
}
