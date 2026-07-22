/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_resource.dart';
import '../api/base_model.dart';
import '../container/container.dart';
import '../storage/storage_downloader.dart';
import 'image_mirror.dart';
import 'local_image_store.dart';
import 'local_store.dart';
import 'offline_error.dart';
import 'sync_image_field.dart';

/// [ApiResource] variant providing keyed offline-cache primitives — the
/// manual counterpart of [OfflineApiModel].
///
/// A resource service writes its own methods against [fetcher] and mirrors
/// whichever records it wants into the [LocalStore] inside the resource
/// namespace ([cacheModel]). Single-record resources (e.g. `/me`) never deal
/// with storage keys — a default slot is used; multi-record resources pass
/// an explicit [key] per record:
///
/// - [remoteOrCached] runs a remote call, caches its result and falls back to
///   the cached record on connectivity failure (server errors are rethrown);
/// - [cacheThenRemote] emits the cached record immediately (when present),
///   then the fresh remote result;
/// - [cacheRecord] / [cachedRecord] / [removeCachedRecord] / [clearCache]
///   are the raw cache primitives (e.g. after a manual PATCH).
///
/// The store is resolved from the container ([LocalStore] must be registered,
/// see `initializeFastEdgy(offline: true)`); when absent every primitive
/// degrades to a plain remote call (or null read).
///
/// Example:
/// ```dart
/// class MeApi extends OfflineApiResource {
///   MeApi() : super('/me');
///
///   Future<User> getMe() => remoteOrCached(
///     User.new,
///     () async => User((await fetcher.get(basePath)).data as Map<String, dynamic>),
///   );
/// }
/// ```
abstract class OfflineApiResource extends ApiResource {
  static const _defaultKey = 'record';

  final LocalStore? _localStore;
  final ImageMirror? _imageMirror;

  /// Create an offline-capable manual API service for a resource.
  ///
  /// [localStore] and [imageMirror] override the container-registered
  /// services (mainly for tests).
  OfflineApiResource(
    super.basePath, {
    super.fetcher,
    LocalStore? localStore,
    ImageMirror? imageMirror,
  }) : _localStore = localStore,
       _imageMirror = imageMirror;

  /// The local store backing this resource, or null when offline is disabled.
  LocalStore? get localStore =>
      _localStore ??
      (hasService<LocalStore>() ? getService<LocalStore>() : null);

  /// The image mirror handling [syncImageFields], or null when the offline
  /// image store is unavailable or no image field is declared.
  ImageMirror? get imageMirror {
    if (syncImageFields.isEmpty) {
      return null;
    }

    if (_imageMirror != null) {
      return _imageMirror;
    }

    final store = localStore;

    if (store == null ||
        !hasService<LocalImageStore>() ||
        !hasService<StorageDownloader>()) {
      return null;
    }

    return ImageMirror(
      store,
      getService<LocalImageStore>(),
      getService<StorageDownloader>(),
    );
  }

  /// Cache namespace of this resource (defaults to [basePath]).
  String get cacheModel => basePath;

  /// Image fields of the cached records to mirror into the local image store,
  /// with the renditions to prefetch.
  List<SyncImageField> get syncImageFields => const [];

  /// Run [remote], cache its result and return it; on connectivity failure
  /// serve the cached record instead (server errors are always rethrown).
  ///
  /// [key] identifies the record inside the resource namespace; omit it for
  /// single-record resources.
  Future<T> remoteOrCached<T extends DynamicSchema<T>>(
    T Function(Map<String, dynamic>) fromJson,
    Future<T> Function() remote, {
    Object key = _defaultKey,
  }) async {
    try {
      final entity = await remote();
      await cacheRecord(entity, key: key);

      return entity;
    } catch (error) {
      if (localStore == null || !isOfflineError(error)) {
        rethrow;
      }

      final cached = await cachedRecord(fromJson, key: key);

      if (cached == null) {
        rethrow;
      }

      return cached;
    }
  }

  /// Emit the cached record (when present), then the fresh [remote] result
  /// (also cached).
  ///
  /// On connectivity failure after a cached emission the stream completes
  /// silently; without any cached data the error is surfaced.
  Stream<T> cacheThenRemote<T extends DynamicSchema<T>>(
    T Function(Map<String, dynamic>) fromJson,
    Future<T> Function() remote, {
    Object key = _defaultKey,
  }) async* {
    final cached = await cachedRecord(fromJson, key: key);

    if (cached != null) {
      yield cached;
    }

    try {
      final entity = await remote();
      await cacheRecord(entity, key: key);

      yield entity;
    } catch (error) {
      if (cached == null || !isOfflineError(error)) {
        rethrow;
      }
    }
  }

  /// Cache [entity] under [key] (mirroring its [syncImageFields] images:
  /// replaced paths are purged, new ones prefetched).
  Future<void> cacheRecord<T extends DynamicSchema<T>>(
    T entity, {
    Object key = _defaultKey,
  }) async {
    final store = localStore;

    if (store == null) {
      return;
    }

    final mirror = imageMirror;
    final previous = mirror == null ? null : await store.get(cacheModel, key);
    final record = entity.toJson();

    await store.put(cacheModel, key, record);

    if (mirror != null) {
      await mirror.refreshNamespace(
        cacheModel,
        syncImageFields,
        prefetchPaths: mirror.changedPaths(previous, record, syncImageFields),
      );
    }
  }

  /// Read the cached record under [key], or null when absent.
  Future<T?> cachedRecord<T extends DynamicSchema<T>>(
    T Function(Map<String, dynamic>) fromJson, {
    Object key = _defaultKey,
  }) async {
    final record = await localStore?.get(cacheModel, key);

    return record == null ? null : fromJson(record);
  }

  /// Remove the cached record under [key].
  Future<void> removeCachedRecord({Object key = _defaultKey}) async {
    await localStore?.delete(cacheModel, key);
    await imageMirror?.refreshNamespace(cacheModel, syncImageFields);
  }

  /// Remove all cached records of this resource.
  Future<void> clearCache() async {
    await localStore?.clear(cacheModel);
    await imageMirror?.refreshNamespace(cacheModel, syncImageFields);
  }
}
