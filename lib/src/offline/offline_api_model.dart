/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';
import '../api/pagination_result.dart';
import '../container/container.dart';
import 'local_store.dart';
import 'offline_error.dart';

/// [ApiModel] variant that mirrors server records into a [LocalStore] to keep
/// reads working offline.
///
/// Behavior:
/// - [list] / [get] are network-first: successful responses are upserted into
///   the local store; on connectivity failure the cached records are served
///   instead (server errors are always rethrown).
/// - [listCacheThenNetwork] / [getCacheThenNetwork] emit the cached data
///   immediately (when present), then the fresh network result.
/// - [create] / [update] / [delete] update the cache on success. Offline
///   writes are rethrown for now (buffered outbox planned in a next phase).
///
/// The store is resolved from the container ([LocalStore] must be registered,
/// see `initializeFastEdgy(offline: true)`); when absent the model behaves
/// exactly like a plain [ApiModel].
///
/// Example:
/// ```dart
/// class WorkspaceUserApi extends OfflineApiModel<WorkspaceUser> {
///   WorkspaceUserApi() : super('/workspace_users');
///
///   @override
///   WorkspaceUser fromJson(Map<String, dynamic> json) => WorkspaceUser(json);
/// }
/// ```
abstract class OfflineApiModel<T extends BaseModel<T>> extends ApiModel<T> {
  final LocalStore? _localStore;

  /// Create an offline-capable API model for a resource.
  ///
  /// [localStore] overrides the container-registered [LocalStore] (mainly for
  /// tests).
  OfflineApiModel(super.basePath, {super.fetcher, LocalStore? localStore})
    : _localStore = localStore;

  /// The local store backing this model, or null when offline is disabled.
  LocalStore? get localStore =>
      _localStore ??
      (hasService<LocalStore>() ? getService<LocalStore>() : null);

  /// Cache namespace of this resource (defaults to [basePath]).
  String get cacheModel => basePath;

  /// Get all cached records of this resource.
  Future<List<T>> cachedList() async {
    final store = localStore;

    if (store == null) {
      return <T>[];
    }

    final records = await store.getAll(cacheModel);

    return records.map(fromJson).toList();
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

      final cached = await cachedList();

      if (cached.isEmpty) {
        rethrow;
      }

      return PaginationResult<T>(
        items: cached,
        total: cached.length,
        limit: cached.length,
        offset: 0,
        totalPages: 1,
      );
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
      await localStore?.put(cacheModel, entity.id!, entity.toJson());
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

    await localStore?.put(cacheModel, entity.id ?? id, entity.toJson());

    return entity;
  }

  @override
  Future<void> delete(Object id, {ApiParams? params}) async {
    // TODO(offline): buffer offline deletes in an outbox and replay on reconnect.
    await super.delete(id, params: params);
    await localStore?.delete(cacheModel, id);
  }

  /// Emit the cached records immediately (when present), then the fresh
  /// network result.
  ///
  /// On connectivity failure after a cached emission the stream completes
  /// silently; without any cached data the error is surfaced.
  Stream<PaginationResult<T>> listCacheThenNetwork({
    ListQuery? query,
    ApiParams? params,
  }) async* {
    final cached = await cachedList();

    if (cached.isNotEmpty) {
      yield PaginationResult<T>(
        items: cached,
        total: cached.length,
        limit: cached.length,
        offset: 0,
        totalPages: 1,
      );
    }

    try {
      yield await _listRemote(query: query, params: params);
    } catch (error) {
      if (cached.isEmpty || !isOfflineError(error)) {
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

  // Network list + cache upsert, without the offline cache fallback.
  Future<PaginationResult<T>> _listRemote({
    ListQuery? query,
    ApiParams? params,
  }) async {
    final store = localStore;
    final result = await super.list(query: query, params: params);

    if (store != null) {
      final records = {
        for (final item in result.items)
          if (item.id != null) '${item.id}': item.toJson(),
      };

      if (_isCompleteResult(query, result)) {
        await store.replaceAll(cacheModel, records);
      } else {
        await store.putAll(cacheModel, records);
      }
    }

    return result;
  }

  // Network get + cache upsert, without the offline cache fallback.
  Future<T> _getRemote(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    final entity = await super.get(id, options: options, params: params);

    if (entity.id != null) {
      await localStore?.put(cacheModel, entity.id!, entity.toJson());
    }

    return entity;
  }

  /// Whether [result] holds the full unfiltered collection, allowing the
  /// cache namespace to be replaced (pruning server-side deletions) instead
  /// of merged.
  bool _isCompleteResult(ListQuery? query, PaginationResult<T> result) {
    if (query?.filter != null) {
      return false;
    }

    final offset =
        query?.offset ??
        (query?.page != null && query?.size != null
            ? (query!.page! - 1) * query.size!
            : 0);

    return offset == 0 && result.items.length >= result.total;
  }
}
