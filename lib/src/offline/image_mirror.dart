/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../logging/logger.dart';
import '../storage/storage_downloader.dart';
import 'local_image_store.dart';
import 'local_store.dart';
import 'pending_upload_store.dart';
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
    Iterable<String>? prefetchPaths,
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
  /// [prefetchPaths] narrows what is downloaded to the paths a single write
  /// touched; left out, every mirrored path is checked and whatever variant is
  /// missing is fetched. A sync leaves it out: a picture whose download failed,
  /// or whose field was declared after the record was mirrored, is only ever
  /// caught up by a pass that looks at all of them.
  Future<void> refresh(
    String namespace,
    Iterable<Map<String, dynamic>> currentRecords,
    List<SyncImageField> fields, {
    Iterable<String>? prefetchPaths,
  }) async {
    if (fields.isEmpty) {
      return;
    }

    // Each path is kept with the variants of the field that named it: the
    // cover of a note and the pictures its text holds are not read at the same
    // size.
    final variantsByPath = <String, Set<ImageVariant>>{};

    for (final record in currentRecords) {
      for (final field in fields) {
        for (final path in imagePathsOfField(record, field)) {
          variantsByPath
              .putIfAbsent(path, () => {})
              .addAll(field.effectiveVariants);
        }
      }
    }

    final current = variantsByPath.keys.toSet();
    final previous = await _namespacePaths(namespace);
    await _records.put(_indexNamespace, namespace, {
      _pathsKey: current.toList(),
    });

    for (final removed in previous.difference(current)) {
      if (!await _isReferenced(removed)) {
        await _images.removePath(removed);
      }
    }

    final wanted = prefetchPaths == null
        ? current
        : current.intersection(prefetchPaths.toSet());

    for (final path in wanted) {
      await _prefetch(path, variantsByPath[path]!);
    }
  }

  /// Take one record into the index and fetch what it brought.
  ///
  /// A read merges one record at a time, and re-indexing the whole namespace
  /// for each of them costs reading every mirrored record and re-reading every
  /// text they hold. Nothing is purged here: what a record stops referencing is
  /// dropped by the next [refresh], which is the pass that sees all of them.
  Future<void> mergeRecord(
    String namespace,
    Map<String, dynamic>? previous,
    Map<String, dynamic> record,
    List<SyncImageField> fields,
  ) async {
    if (fields.isEmpty) {
      return;
    }

    final variantsByPath = <String, Set<ImageVariant>>{};

    for (final field in fields) {
      for (final path in imagePathsOfField(record, field)) {
        variantsByPath
            .putIfAbsent(path, () => {})
            .addAll(field.effectiveVariants);
      }
    }

    final known = await _namespacePaths(namespace);
    final added = variantsByPath.keys.toSet().difference(known);

    if (added.isNotEmpty) {
      await _records.put(_indexNamespace, namespace, {
        _pathsKey: known.union(added).toList(),
      });
    }

    for (final path in changedPaths(previous, record, fields)) {
      final variants = variantsByPath[path];

      if (variants != null) {
        await _prefetch(path, variants);
      }
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
      changed.addAll(
        imagePathsOfField(
          record,
          field,
        ).difference(imagePathsOfField(previous, field)),
      );
    }

    return changed;
  }

  Future<void> _prefetch(String path, Iterable<ImageVariant> variants) async {
    if (pendingUploadIdOf(path) != null) {
      // A file still waiting for its upload has nothing to download: its bytes
      // are already local, and the server knows no such path. Trying would warn
      // on every pass until the upload goes through.
      return;
    }

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

/// The image paths [field] holds in [value]: the values found under its name,
/// or what its own reader makes of them (a rich text names its pictures inside
/// the text rather than being one).
Set<String> imagePathsOfField(Object? value, SyncImageField field) {
  final found = imagePathsOf(value, field.field);
  final read = field.paths;

  if (read == null) {
    return found;
  }

  return {for (final value in found) ...read(value)};
}

/// Every non-empty string held under [field] in [value], at any depth: a
/// payload carries its images on the record itself, on the relations its field
/// selection embedded, and on the rows of an envelope.
Set<String> imagePathsOf(Object? value, String field) {
  final paths = <String>{};

  _collectImagePaths(value, field, paths);

  return paths;
}

void _collectImagePaths(Object? value, String field, Set<String> into) {
  if (value is Map) {
    for (final entry in value.entries) {
      final nested = entry.value;

      if (entry.key == field && nested is String && nested.isNotEmpty) {
        into.add(nested);
      } else {
        _collectImagePaths(nested, field, into);
      }
    }
  } else if (value is List) {
    for (final item in value) {
      _collectImagePaths(item, field, into);
    }
  }
}
