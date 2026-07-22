/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_helpers.dart';
import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';
import '../api/pagination_result.dart';
import '../container/container.dart';
import '../storage/storage_downloader.dart';
import 'image_mirror.dart';
import 'local_image_store.dart';
import 'local_store.dart';
import 'offline_error.dart';
import 'sync_image_field.dart';

/// [ApiModel] variant that mirrors server records into a [LocalStore] to keep
/// reads working offline.
///
/// The cache contract is decoupled from the UI pagination and filters:
///
/// - [sync] is the only writer allowed to prune: it walks the WHOLE collection
///   (auto-paginated, with [syncFields] preloading) and transactionally
///   replaces the namespace — the cache always means "the full collection as
///   of the last sync".
/// - [list] / [get] are network-first and deep-merge fetched records by id
///   into the cache (freshness without pruning: a partial page or a narrow
///   X-Fields selection can never poison the namespace); on connectivity
///   failure the query is evaluated locally against the cached records
///   (order_by, offset/limit — filters are not evaluated locally yet and are
///   ignored offline). Server errors are always rethrown.
/// - [listCacheThenNetwork] / [getCacheThenNetwork] emit the locally evaluated
///   data immediately (when present), then the fresh network result.
/// - [create] / [update] / [delete] update the cache on success. Offline
///   writes are rethrown for now (buffered outbox planned in a next phase).
///
/// The store is resolved from the container ([LocalStore] must be registered,
/// see `initializeFastEdgy(offline: true)`); when absent the model behaves
/// exactly like a plain [ApiModel].
///
/// Example:
/// ```dart
/// class WorkspaceApi extends OfflineApiModel<Workspace> {
///   WorkspaceApi() : super('/workspaces');
///
///   @override
///   dynamic get syncFields => 'id,name,slug,image_url';
///
///   @override
///   Workspace fromJson(Map<String, dynamic> json) => Workspace(json);
/// }
///
/// await useWorkspaceApi().sync();
/// ```
abstract class OfflineApiModel<T extends BaseModel<T>> extends ApiModel<T> {
  final LocalStore? _localStore;
  final ImageMirror? _imageMirror;

  /// Create an offline-capable API model for a resource.
  ///
  /// [localStore] and [imageMirror] override the container-registered
  /// services (mainly for tests).
  OfflineApiModel(
    super.basePath, {
    super.fetcher,
    LocalStore? localStore,
    ImageMirror? imageMirror,
  }) : _localStore = localStore,
       _imageMirror = imageMirror;

  /// The local store backing this model, or null when offline is disabled.
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

  /// X-Fields used by [sync] to mirror the collection (relations to preload).
  /// Null selects the default server fields.
  dynamic get syncFields => null;

  /// Image fields of the synced records to mirror into the local image store
  /// (must be part of [syncFields]), with the renditions to prefetch.
  List<SyncImageField> get syncImageFields => const [];

  /// Page size used by [sync] while walking the collection (transport detail,
  /// unrelated to the cache contract).
  int get syncPageSize => 200;

  /// Mirror the whole collection into the local store.
  ///
  /// Fetches every record (auto-paginated by [syncPageSize], preloading
  /// [syncFields]) then transactionally replaces the namespace, pruning
  /// records deleted on the server. No-op when offline is disabled.
  Future<void> sync({ApiParams? params}) async {
    final store = localStore;

    if (store == null) {
      return;
    }

    final records = <String, Map<String, dynamic>>{};
    var offset = 0;

    while (true) {
      final page = await super.list(
        query: ListQuery(
          fields: syncFields,
          limit: syncPageSize,
          offset: offset,
        ),
        params: params,
      );

      for (final item in page.items) {
        if (item.id != null) {
          records['${item.id}'] = item.toJson();
        }
      }

      offset += page.items.length;

      if (page.items.isEmpty || offset >= page.total) {
        break;
      }
    }

    await store.replaceAll(cacheModel, records);

    final mirror = imageMirror;

    if (mirror != null) {
      final paths = <String>{
        for (final record in records.values)
          for (final field in syncImageFields)
            if (record[field.field] is String &&
                (record[field.field] as String).isNotEmpty)
              record[field.field] as String,
      };

      await mirror.refreshNamespace(
        cacheModel,
        syncImageFields,
        prefetchPaths: paths,
      );
    }
  }

  /// Get all cached records of this resource (raw namespace read).
  Future<List<T>> cachedList() async {
    final store = localStore;

    if (store == null) {
      return <T>[];
    }

    final records = await store.getAll(cacheModel);

    return records.map(fromJson).toList();
  }

  /// Evaluate [query] against the cached records.
  ///
  /// Applies order_by then offset/limit locally and returns an honest
  /// [PaginationResult] (total = cached collection size). Filters are not
  /// evaluated locally yet: a filtered query serves the unfiltered
  /// collection.
  Future<PaginationResult<T>> cachedQuery([ListQuery? query]) async {
    final all = _applyOrderBy(await cachedList(), query?.orderBy);
    final offset = _queryOffset(query);
    final limit = query?.limit ?? query?.size;
    final end = limit == null ? all.length : offset + limit;
    final items = offset >= all.length
        ? <T>[]
        : all.sublist(offset, end > all.length ? all.length : end);

    return PaginationResult<T>(
      items: items,
      total: all.length,
      limit: limit ?? all.length,
      offset: offset,
      totalPages: limit == null || limit == 0
          ? (all.isEmpty ? 0 : 1)
          : (all.length / limit).ceil(),
    );
  }

  /// Get a cached record by id, or null when absent.
  Future<T?> cachedGet(Object id) async {
    final store = localStore;

    if (store == null) {
      return null;
    }

    final record = await store.get(cacheModel, id);

    return record == null ? null : fromJson(record);
  }

  /// Remove all cached records of this resource.
  Future<void> clearCache() async {
    await localStore?.clear(cacheModel);
    await imageMirror?.refreshNamespace(cacheModel, syncImageFields);
  }

  @override
  Future<PaginationResult<T>> list({
    ListQuery? query,
    ApiParams? params,
  }) async {
    try {
      return await _listRemote(query: query, params: params);
    } catch (error) {
      if (localStore == null || !isOfflineError(error)) {
        rethrow;
      }

      final cached = await cachedQuery(query);

      if (cached.total == 0) {
        rethrow;
      }

      return cached;
    }
  }

  @override
  Future<T> get(Object id, {FieldsOptions? options, ApiParams? params}) async {
    try {
      return await _getRemote(id, options: options, params: params);
    } catch (error) {
      if (localStore == null || !isOfflineError(error)) {
        rethrow;
      }

      final cached = await cachedGet(id);

      if (cached == null) {
        rethrow;
      }

      return cached;
    }
  }

  @override
  Future<T> create(
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    // TODO(offline): buffer offline creates in an outbox and replay on reconnect.
    final entity = await super.create(
      payload,
      options: options,
      params: params,
    );

    if (entity.id != null) {
      await _mergeRecord(entity.id!, entity.toJson());
    }

    return entity;
  }

  @override
  Future<T> update(
    Object id,
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    // TODO(offline): buffer offline updates in an outbox and replay on reconnect.
    final entity = await super.update(
      id,
      payload,
      options: options,
      params: params,
    );

    await _mergeRecord(entity.id ?? id, entity.toJson());

    return entity;
  }

  @override
  Future<void> delete(Object id, {ApiParams? params}) async {
    // TODO(offline): buffer offline deletes in an outbox and replay on reconnect.
    await super.delete(id, params: params);
    await localStore?.delete(cacheModel, id);
    await imageMirror?.refreshNamespace(cacheModel, syncImageFields);
  }

  /// Emit the locally evaluated [query] immediately (when the cache holds
  /// records), then the fresh network result.
  ///
  /// On connectivity failure after a cached emission the stream completes
  /// silently; without any cached data the error is surfaced.
  Stream<PaginationResult<T>> listCacheThenNetwork({
    ListQuery? query,
    ApiParams? params,
  }) async* {
    final cached = await cachedQuery(query);

    if (cached.total > 0) {
      yield cached;
    }

    try {
      yield await _listRemote(query: query, params: params);
    } catch (error) {
      if (cached.total == 0 || !isOfflineError(error)) {
        rethrow;
      }
    }
  }

  /// Emit the cached record immediately (when present), then the fresh
  /// network result.
  ///
  /// On connectivity failure after a cached emission the stream completes
  /// silently; without any cached data the error is surfaced.
  Stream<T> getCacheThenNetwork(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async* {
    final cached = await cachedGet(id);

    if (cached != null) {
      yield cached;
    }

    try {
      yield await _getRemote(id, options: options, params: params);
    } catch (error) {
      if (cached == null || !isOfflineError(error)) {
        rethrow;
      }
    }
  }

  // Network list + per-record deep merge into the cache (never prunes — only
  // sync() is allowed to), without the offline cache fallback.
  Future<PaginationResult<T>> _listRemote({
    ListQuery? query,
    ApiParams? params,
  }) async {
    final store = localStore;
    final result = await super.list(query: query, params: params);

    if (store != null && result.items.isNotEmpty) {
      final existing = {
        for (final record in await store.getAll(cacheModel))
          '${record['id']}': record,
      };
      final records = {
        for (final item in result.items)
          if (item.id != null)
            '${item.id}': {...?existing['${item.id}'], ...item.toJson()},
      };

      await store.putAll(cacheModel, records);

      final mirror = imageMirror;

      if (mirror != null) {
        final changed = <String>{
          for (final entry in records.entries)
            ...mirror.changedPaths(
              existing[entry.key],
              entry.value,
              syncImageFields,
            ),
        };

        await mirror.refreshNamespace(
          cacheModel,
          syncImageFields,
          prefetchPaths: changed,
        );
      }
    }

    return result;
  }

  // Network get + per-record deep merge into the cache, without the offline
  // cache fallback.
  Future<T> _getRemote(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    final entity = await super.get(id, options: options, params: params);

    if (entity.id != null) {
      await _mergeRecord(entity.id!, entity.toJson());
    }

    return entity;
  }

  // Merge a fetched record over its cached version (fresh fields win, fields
  // absent from the fetch — e.g. a narrow X-Fields selection — are retained).
  Future<void> _mergeRecord(Object id, Map<String, dynamic> json) async {
    final store = localStore;

    if (store == null) {
      return;
    }

    final existing = await store.get(cacheModel, id);
    final merged = {...?existing, ...json};
    await store.put(cacheModel, id, merged);

    final mirror = imageMirror;

    if (mirror != null) {
      await mirror.refreshNamespace(
        cacheModel,
        syncImageFields,
        prefetchPaths: mirror.changedPaths(existing, merged, syncImageFields),
      );
    }
  }

  int _queryOffset(ListQuery? query) {
    if (query?.offset != null) {
      return query!.offset!;
    }

    if (query?.page != null && query?.size != null) {
      return (query!.page! - 1) * query.size!;
    }

    return 0;
  }

  List<T> _applyOrderBy(List<T> items, dynamic orderBy) {
    final encoded = ApiHelpers.encodeOrderBy(orderBy);

    if (encoded.isEmpty) {
      return items;
    }

    final terms = encoded
        .split(',')
        .map((term) {
          final parts = term.split(':');

          return (
            parts.first.trim(),
            parts.length > 1 ? parts[1].trim() : 'asc',
          );
        })
        .where((term) => term.$1.isNotEmpty)
        .toList();

    if (terms.isEmpty) {
      return items;
    }

    final sorted = [...items];
    sorted.sort((a, b) {
      for (final (field, direction) in terms) {
        final comparison = _compareValues(
          a.getField<dynamic>(field),
          b.getField<dynamic>(field),
        );

        if (comparison != 0) {
          return direction == 'desc' ? -comparison : comparison;
        }
      }

      return 0;
    });

    return sorted;
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) {
      return 0;
    }

    if (a == null) {
      return 1;
    }

    if (b == null) {
      return -1;
    }

    if (a is num && b is num) {
      return a.compareTo(b);
    }

    if (a is DateTime && b is DateTime) {
      return a.compareTo(b);
    }

    if (a is bool && b is bool) {
      return (a ? 1 : 0).compareTo(b ? 1 : 0);
    }

    return '$a'.toLowerCase().compareTo('$b'.toLowerCase());
  }
}
