/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../logging/logger.dart';
import '../storage/storage_downloader.dart';
import 'local_image_store.dart';
import 'local_store.dart';
import '../api/sync_image_field.dart';

/// Mirrors the images referenced by synced records into the [LocalImageStore].
///
/// Bookkeeping: the set of storage paths referenced by each record namespace
/// is indexed in the record [LocalStore] (reserved `_image_paths` namespace).
/// After every cache write the namespace index is recomputed from the cached
/// records; a path no longer referenced by ANY namespace has its blobs
/// deleted, and missing declared variants of (re)appearing paths are
/// downloaded. A failed download never fails the sync (logged, retried on the
/// next pass since the variant stays missing).
class ImageMirror {
  static const _indexNamespace = '_image_paths';
  static const _pathsKey = 'paths';

  final LocalStore _records;
  final LocalImageStore _images;
  final StorageDownloader _downloader;
  final _logger = getLogger('ImageMirror');

  ImageMirror(this._records, this._images, this._downloader);

  /// Re-index [namespace] from its cached records (read from the record
  /// store), purge blobs of paths no longer referenced anywhere, and
  /// prefetch the declared variants of [prefetchPaths].
  Future<void> refreshNamespace(
    String namespace,
    List<SyncImageField> fields, {
    Iterable<String> prefetchPaths = const [],
  }) async {
    if (fields.isEmpty) {
      return;
    }

    await refresh(
      namespace,
      await _records.getAll(namespace),
      fields,
      prefetchPaths: prefetchPaths,
    );
  }

  /// Same as [refreshNamespace] with the current records provided by the
  /// caller (e.g. a replica table instead of the JSON record store) —
  /// [namespace] only keys the path index.
  Future<void> refresh(
    String namespace,
    Iterable<Map<String, dynamic>> currentRecords,
    List<SyncImageField> fields, {
    Iterable<String> prefetchPaths = const [],
  }) async {
    if (fields.isEmpty) {
      return;
    }

    final current = <String>{};

    for (final record in currentRecords) {
      for (final field in fields) {
        final path = record[field.field];

        if (path is String && path.isNotEmpty) {
          current.add(path);
        }
      }
    }

    final previous = await _namespacePaths(namespace);
    await _records.put(_indexNamespace, namespace, {
      _pathsKey: current.toList(),
    });

    for (final removed in previous.difference(current)) {
      if (!await _isReferenced(removed)) {
        await _images.removePath(removed);
      }
    }

    final variantsByPath = <String, Set<ImageVariant>>{};

    for (final field in fields) {
      for (final path in prefetchPaths) {
        if (current.contains(path)) {
          variantsByPath
              .putIfAbsent(path, () => {})
              .addAll(field.effectiveVariants);
        }
      }
    }

    for (final entry in variantsByPath.entries) {
      await _prefetch(entry.key, entry.value);
    }
  }

  /// The declared image paths of [record] whose value differs from
  /// [previous] (new records included) — the paths worth prefetching after a
  /// merge.
  Set<String> changedPaths(
    Map<String, dynamic>? previous,
    Map<String, dynamic> record,
    List<SyncImageField> fields,
  ) {
    final changed = <String>{};

    for (final field in fields) {
      final value = record[field.field];

      if (value is String &&
          value.isNotEmpty &&
          value != previous?[field.field]) {
        changed.add(value);
      }
    }

    return changed;
  }

  Future<void> _prefetch(String path, Iterable<ImageVariant> variants) async {
    for (final variant in variants) {
      if (await _images.hasVariant(path, variant.key)) {
        continue;
      }

      try {
        final bytes = variant.isProcessed
            ? await _downloader.downloadPath(
                path,
                width: variant.width,
                height: variant.height,
                resizeMode: variant.mode,
                outputFormat: variant.format,
              )
            : await _downloader.downloadPath(path);

        await _images.putVariant(
          path,
          variant.key,
          bytes,
          width: variant.width,
          height: variant.height,
        );
      } catch (error) {
        _logger.warning('Failed to mirror image $path (${variant.key})', error);
      }
    }
  }

  Future<Set<String>> _namespacePaths(String namespace) async {
    final record = await _records.get(_indexNamespace, namespace);
    final paths = record?[_pathsKey];

    return paths is List ? paths.whereType<String>().toSet() : <String>{};
  }

  Future<bool> _isReferenced(String path) async {
    for (final index in await _records.getAll(_indexNamespace)) {
      final paths = index[_pathsKey];

      if (paths is List && paths.contains(path)) {
        return true;
      }
    }

    return false;
  }
}
