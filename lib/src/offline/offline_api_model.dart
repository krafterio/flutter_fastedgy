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
import '../logging/logger.dart';
import '../storage/storage_downloader.dart';
import 'image_mirror.dart';
import 'local_image_store.dart';
import 'local_schema.dart';
import 'local_store.dart';
import 'offline_error.dart';
import 'outbox.dart';
import 'sync_engine.dart';
import 'replica.dart';
import 'sync_image_field.dart';

/// [ApiModel] variant that mirrors server records locally to keep reads
/// working offline.
///
/// Two storage strategies share the same contract (the cache is decoupled
/// from the UI pagination and filters; [sync] is the only writer allowed to
/// prune; `list`/`get` deep-merge fetched records without pruning; server
/// errors are always rethrown):
///
/// - **Replicated** (opt-in via [modelName]): records live in typed
///   [ReplicaStore] tables scoped by [replicaScope]; offline queries are
///   compiled to SQL with full server parity (filters, nested order_by).
/// - **JSON namespace** (default): records live in the [LocalStore] as JSON;
///   offline queries evaluate order_by/limit/offset in memory and ignore
///   filters.
///
/// Example:
/// ```dart
/// class UserApi extends OfflineApiModel<User> {
///   // `modelName` resolves the resource segment (`users`) from the metadata
///   // and enables replication; only the runtime scope is left to declare.
///   UserApi() : super('/{workspace}', modelName: 'user');
///
///   @override
///   String get replicaScope => currentWorkspaceSlug;
/// }
/// ```
abstract class OfflineApiModel<T extends BaseModel<T>> extends ApiModel<T> {
  final LocalStore? _localStore;
  final ImageMirror? _imageMirror;
  final Replica? _replica;
  final Outbox? _outbox;

  /// Create an offline-capable API model for a resource.
  ///
  /// [localStore], [imageMirror] and [replica] override the
  /// container-registered services (mainly for tests).
  OfflineApiModel(
    super.basePath, {
    super.modelName,
    super.fetcher,
    LocalStore? localStore,
    ImageMirror? imageMirror,
    Replica? replica,
    Outbox? outbox,
  }) : _localStore = localStore,
       _imageMirror = imageMirror,
       _replica = replica,
       _outbox = outbox;

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

  /// The replication service, or null when replication is unavailable or not
  /// requested ([modelName] null keeps the JSON namespace cache).
  Replica? get replica =>
      _replica ??
      (modelName != null && hasService<Replica>()
          ? getService<Replica>()
          : null);

  /// The outbox buffering offline writes, or null when unavailable.
  Outbox? get outbox =>
      _outbox ?? (hasService<Outbox>() ? getService<Outbox>() : null);

  /// Cache namespace of this resource: [modelName] when given (stable), else
  /// [basePath].
  String get cacheModel => modelName ?? basePath;

  /// The base path stored on buffered operations and used for their replay.
  ///
  /// The resolved path with its `{workspace}` placeholder substituted by the
  /// current [replicaScope] **at enqueue time**: a buffered write must replay
  /// against the context it was made in, not whatever context is active when
  /// connectivity comes back. (Resolution runs in [_replicaContext] before any
  /// read of this getter.)
  String get outboxBasePath => replicaScope.isEmpty
      ? resolvedBasePath
      : resolvedBasePath.replaceAll('{workspace}', replicaScope);

  /// Replica scope of this resource's rows (e.g. the current workspace
  /// slug); '' for globally-scoped models.
  String get replicaScope => '';

  /// Replica scope of a related [model] traversed by a filter or order_by
  /// path (defaults to [replicaScope] for every model).
  String replicaScopeFor(String model) => replicaScope;

  /// X-Fields used by [sync] to mirror the collection (relations to preload).
  /// Null selects the default server fields.
  dynamic get syncFields => null;

  /// Page size used by [sync] while walking the collection (transport detail,
  /// unrelated to the cache contract).
  int get syncPageSize => 200;

  /// Image fields of the synced records to mirror into the local image store
  /// (must be part of [syncFields]), with the renditions to prefetch.
  List<SyncImageField> get syncImageFields => const [];

  /// Mirror the collection into the local store, incrementally.
  ///
  /// Walks a paginated **manifest** of the collection (`X-Fields:
  /// id,updated_at` — a few bytes per record), diffs it against the local
  /// mirror, then fetches only the new/changed records in batches
  /// (`X-Filter: ["id","in",[...]]` with [syncFields]) and prunes the ids
  /// gone from the server — deletions are derived from the set difference,
  /// covering every server-side deletion path (SQL cascades included), and
  /// the `updated_at` comparison is server-value vs server-value (no device
  /// clock). Pending offline records (temporary ids) are never pruned.
  /// No-op when offline is disabled.
  Future<void> sync({ApiParams? params}) async {
    final ctx = await _replicaContext();

    if (ctx == null && localStore == null) {
      return;
    }

    if (ctx != null) {
      await ctx.replica.ensure(ctx.model.name);
    }

    // 0) Replay the buffered writes first so the merge happens server-side
    // before the pull; whatever could not be flushed (still offline, 5xx) is
    // protected below.
    if (hasService<SyncEngine>()) {
      try {
        await getService<SyncEngine>().flush();
      } catch (error) {
        // The pull still runs: whatever stayed buffered is protected below.
        getLogger('OfflineApiModel').warning('Outbox flush failed: $error');
      }
    }

    final pendingByRecord = <String, List<PendingOperation>>{};

    for (final operation in await outbox?.all() ?? const <PendingOperation>[]) {
      if (operation.basePath == outboxBasePath && operation.recordId != null) {
        pendingByRecord
            .putIfAbsent('${operation.recordId}', () => [])
            .add(operation);
      }
    }

    // 1) Paginated server manifest: id → updated_at.
    final serverManifest = <String, String?>{};
    var offset = 0;

    while (true) {
      final page = await super.list(
        query: ListQuery(
          fields: 'id,updated_at',
          limit: syncPageSize,
          offset: offset,
          orderBy: 'id',
        ),
        params: params,
      );

      for (final item in page.items) {
        if (item.id != null) {
          serverManifest['${item.id}'] = item.toJson()['updated_at'] as String?;
        }
      }

      offset += page.items.length;

      if (page.items.isEmpty || offset >= page.total) {
        break;
      }
    }

    // 2) Diff against the local manifest.
    final localManifest = ctx != null
        ? await ctx.replica.store.manifest(ctx.model, ctx.scope)
        : {
            for (final record in await localStore!.getAll(cacheModel))
              '${record['id']}': record['updated_at'] as String?,
          };

    final toFetch = <String>[
      for (final entry in serverManifest.entries)
        if (localManifest[entry.key] == null ||
            entry.value == null ||
            localManifest[entry.key] != entry.value)
          entry.key,
    ];
    // Records with buffered writes are never pruned nor clobbered blindly:
    // the outbox replay is the authority on their fate.
    final toDelete = <String>[
      for (final id in localManifest.keys)
        if (!serverManifest.containsKey(id) &&
            !id.startsWith('-') &&
            !pendingByRecord.containsKey(id))
          id,
    ];

    // 3) Batched fetch of the needed records only.
    final records = <Map<String, dynamic>>[];

    for (var start = 0; start < toFetch.length; start += syncPageSize) {
      final end = start + syncPageSize > toFetch.length
          ? toFetch.length
          : start + syncPageSize;
      final ids = toFetch
          .sublist(start, end)
          .map((id) => int.tryParse(id) ?? id)
          .toList();
      var chunkOffset = 0;

      while (true) {
        final page = await super.list(
          query: ListQuery(
            fields: syncFields,
            filter: ['id', 'in', ids],
            limit: syncPageSize,
            offset: chunkOffset,
            orderBy: 'id',
          ),
          params: params,
        );

        for (final item in page.items) {
          if (item.id != null) {
            records.add(item.toJson());
          }
        }

        chunkOffset += page.items.length;

        if (page.items.isEmpty || chunkOffset >= page.total) {
          break;
        }
      }
    }

    // 4) Transactional apply + image mirror refresh.
    if (ctx != null) {
      await ctx.replica.store.applyDelta(
        ctx.model,
        ctx.scope,
        records,
        toDelete,
      );
      await _reapplyPending(pendingByRecord, ctx: ctx);
      await imageMirror?.refresh(
        ctx.imageNamespace,
        await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
        syncImageFields,
        prefetchPaths: _imagePaths(records),
      );
    } else {
      final store = localStore!;

      for (final id in toDelete) {
        await store.delete(cacheModel, id);
      }

      await store.putAll(cacheModel, {
        for (final record in records) '${record['id']}': record,
      });
      await _reapplyPending(pendingByRecord);
      await imageMirror?.refreshNamespace(
        cacheModel,
        syncImageFields,
        prefetchPaths: _imagePaths(records),
      );
    }
  }

  /// Re-apply the optimistic effect of the still-buffered operations on top
  /// of the freshly pulled records, so a sync never visually reverts a write
  /// the user made offline.
  Future<void> _reapplyPending(
    Map<String, List<PendingOperation>> pendingByRecord, {
    _ReplicaContext? ctx,
  }) async {
    for (final entry in pendingByRecord.entries) {
      for (final operation in entry.value) {
        if (operation.method == 'PATCH' && operation.payload != null) {
          if (ctx != null) {
            final current = await ctx.replica.store.getById(
              ctx.model.name,
              ctx.scope,
              operation.recordId!,
            );

            if (current != null) {
              await ctx.replica.store.upsertAll(ctx.model, ctx.scope, [
                {...current, ...operation.payload!},
              ]);
            }
          } else {
            final current = await localStore!.get(
              cacheModel,
              operation.recordId!,
            );

            if (current != null) {
              await localStore!.put(cacheModel, operation.recordId!, {
                ...current,
                ...operation.payload!,
              });
            }
          }
        } else if (operation.method == 'DELETE') {
          if (ctx != null) {
            await ctx.replica.store.deleteById(
              ctx.model.name,
              ctx.scope,
              operation.recordId!,
            );
          } else {
            await localStore!.delete(cacheModel, operation.recordId!);
          }
        }
      }
    }
  }

  /// Get all cached records of this resource (raw namespace/scope read).
  Future<List<T>> cachedList() async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      final records = await ctx.replica.store.getAll(ctx.model.name, ctx.scope);

      return records.map(fromJson).toList();
    }

    final store = localStore;

    if (store == null) {
      return <T>[];
    }

    return (await store.getAll(cacheModel)).map(fromJson).toList();
  }

  /// Evaluate [query] against the cached records.
  ///
  /// Replicated models compile the query (filters included) to SQL with
  /// server parity; the JSON namespace mode applies order_by then
  /// offset/limit in memory and serves the unfiltered collection for a
  /// filtered query.
  Future<PaginationResult<T>> cachedQuery([ListQuery? query]) async {
    final ctx = await _replicaContext();
    final offset = _queryOffset(query);
    final limit = query?.limit ?? query?.size;

    if (ctx != null) {
      final result = await ctx.replica.store.query(
        ctx.schema,
        ctx.model.name,
        scope: ctx.scope,
        scopeOf: replicaScopeFor,
        filter: query?.filter,
        orderBy: query?.orderBy,
        limit: limit,
        offset: offset > 0 ? offset : null,
      );

      return PaginationResult<T>(
        items: result.records.map(fromJson).toList(),
        total: result.total,
        limit: limit ?? result.total,
        offset: offset,
        totalPages: _totalPages(result.total, limit),
      );
    }

    final all = _applyOrderBy(await cachedList(), query?.orderBy);
    final end = limit == null ? all.length : offset + limit;
    final items = offset >= all.length
        ? <T>[]
        : all.sublist(offset, end > all.length ? all.length : end);

    return PaginationResult<T>(
      items: items,
      total: all.length,
      limit: limit ?? all.length,
      offset: offset,
      totalPages: _totalPages(all.length, limit),
    );
  }

  /// Get a cached record by id, or null when absent.
  Future<T?> cachedGet(Object id) async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      final record = await ctx.replica.store.getById(
        ctx.model.name,
        ctx.scope,
        id,
      );

      return record == null ? null : fromJson(record);
    }

    final record = await localStore?.get(cacheModel, id);

    return record == null ? null : fromJson(record);
  }

  /// Remove all cached records of this resource (current scope).
  Future<void> clearCache() async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      await ctx.replica.store.clearScope(ctx.model.name, ctx.scope);
      await imageMirror?.refresh(ctx.imageNamespace, const [], syncImageFields);
      return;
    }

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
      if (!_canFallback(error)) {
        rethrow;
      }

      final fallback = await _offlineListFallback(query);

      if (fallback == null) {
        rethrow;
      }

      return fallback;
    }
  }

  @override
  Future<T> get(Object id, {FieldsOptions? options, ApiParams? params}) async {
    try {
      return await _getRemote(id, options: options, params: params);
    } catch (error) {
      if (!_canFallback(error)) {
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
    try {
      final entity = await super.create(
        payload,
        options: options,
        params: params,
      );

      if (entity.id != null) {
        await _mergeRecord(entity.id!, entity.toJson());
      }

      return entity;
    } catch (error) {
      final outbox = this.outbox;

      if (outbox == null || !isOfflineError(error)) {
        rethrow;
      }

      // Optimistic offline create: a negative temporary id marks the record
      // as pending until the outbox replay assigns the real one.
      final tempId = -DateTime.now().microsecondsSinceEpoch;
      final record = {
        ...payload.toJson(),
        'id': tempId,
        '_offline_pending': true,
      };
      final cache = await _cacheContext();

      await _mergeRecord(tempId, record);
      await outbox.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: 'POST',
          basePath: outboxBasePath,
          recordId: tempId,
          payload: payload.toJson(),
          createdAt: createdAt,
          cache: cache,
        ),
      );
      notifyChanged(ResourceChangeType.created, tempId);

      return fromJson(record);
    }
  }

  @override
  Future<T> update(
    Object id,
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    try {
      final entity = await super.update(
        id,
        payload,
        options: options,
        params: params,
      );

      await _mergeRecord(entity.id ?? id, entity.toJson());

      return entity;
    } catch (error) {
      final outbox = this.outbox;

      if (outbox == null || !isOfflineError(error)) {
        rethrow;
      }

      final cache = await _cacheContext();
      // Base snapshot of the three-way merge: the record as known before the
      // optimistic local write below.
      final base = (await cachedGet(id))?.toJson();

      await _mergeRecord(id, {
        ...payload.toJson(),
        'id': id,
        '_offline_pending': true,
      });
      await outbox.enqueue(
        (opId, createdAt) => PendingOperation(
          id: opId,
          method: 'PATCH',
          basePath: outboxBasePath,
          recordId: id,
          payload: payload.toJson(),
          createdAt: createdAt,
          base: base,
          cache: cache,
        ),
      );
      notifyChanged(ResourceChangeType.updated, id);

      final cached = await cachedGet(id);

      return cached ?? fromJson({...payload.toJson(), 'id': id});
    }
  }

  @override
  Future<void> delete(Object id, {ApiParams? params}) async {
    // Resolve the effective path up front: the temp-id branch below reads
    // [outboxBasePath] without going through the network or _replicaContext.
    await resolvePath();

    // A temporary id never existed server-side: cancel locally without any
    // network call (online or not). If the create already left the queue
    // (replay in flight or done), buffer a delete — the engine resolves the
    // temporary id through its persisted map.
    final temp = id is int && id < 0;

    if (temp && outbox != null) {
      if (!await outbox!.cancelCreateFor(outboxBasePath, id)) {
        final cache = await _cacheContext();

        await outbox!.enqueue(
          (opId, createdAt) => PendingOperation(
            id: opId,
            method: 'DELETE',
            basePath: outboxBasePath,
            recordId: id,
            createdAt: createdAt,
            cache: cache,
          ),
        );
      }

      notifyChanged(ResourceChangeType.deleted, id);
      await _removeLocal(id);

      return;
    }

    try {
      await super.delete(id, params: params);
    } catch (error) {
      final outbox = this.outbox;

      if (outbox == null || !isOfflineError(error)) {
        rethrow;
      }

      // Deleting a record that only exists as a pending offline create
      // cancels both operations.
      if (!await outbox.cancelCreateFor(outboxBasePath, id)) {
        final cache = await _cacheContext();
        final base = (await cachedGet(id))?.toJson();

        await outbox.enqueue(
          (opId, createdAt) => PendingOperation(
            id: opId,
            method: 'DELETE',
            basePath: outboxBasePath,
            recordId: id,
            createdAt: createdAt,
            base: base,
            cache: cache,
          ),
        );
      }

      notifyChanged(ResourceChangeType.deleted, id);
    }

    await _removeLocal(id);
  }

  Future<OutboxCacheContext> _cacheContext() async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      return OutboxCacheContext(
        kind: 'replica',
        namespace: cacheModel,
        model: ctx.model.name,
        scope: ctx.scope,
      );
    }

    return OutboxCacheContext(kind: 'json', namespace: cacheModel);
  }

  Future<void> _removeLocal(Object id) async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      await ctx.replica.store.deleteById(ctx.model.name, ctx.scope, id);
      await imageMirror?.refresh(
        ctx.imageNamespace,
        await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
        syncImageFields,
      );
      return;
    }

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
      if (cached.total == 0 || !_canFallback(error)) {
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
      if (cached == null || !_canFallback(error)) {
        rethrow;
      }
    }
  }

  bool _canFallback(Object error) =>
      (localStore != null || replica != null) && isOfflineError(error);

  Future<PaginationResult<T>?> _offlineListFallback(ListQuery? query) async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      // A filtered query may legitimately match nothing: only rethrow when
      // the scope was never mirrored at all.
      if (await ctx.replica.store.countScope(ctx.model.name, ctx.scope) == 0) {
        return null;
      }

      return cachedQuery(query);
    }

    final cached = await cachedQuery(query);

    return cached.total == 0 ? null : cached;
  }

  // Network list + per-record deep merge into the cache (never prunes — only
  // sync() is allowed to), without the offline cache fallback.
  Future<PaginationResult<T>> _listRemote({
    ListQuery? query,
    ApiParams? params,
  }) async {
    final result = await super.list(query: query, params: params);

    if (result.items.isNotEmpty) {
      final changed = <String>{};
      final mirror = imageMirror;
      final ctx = await _replicaContext();

      if (ctx != null) {
        final merged = <Map<String, dynamic>>[];

        for (final item in result.items) {
          if (item.id == null) {
            continue;
          }

          final existing = await ctx.replica.store.getById(
            ctx.model.name,
            ctx.scope,
            item.id!,
          );
          final record = {...?existing, ...item.toJson()};
          merged.add(record);

          if (mirror != null) {
            changed.addAll(
              mirror.changedPaths(existing, record, syncImageFields),
            );
          }
        }

        await ctx.replica.ensure(ctx.model.name);
        await ctx.replica.store.upsertAll(ctx.model, ctx.scope, merged);

        if (mirror != null) {
          await mirror.refresh(
            ctx.imageNamespace,
            await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
            syncImageFields,
            prefetchPaths: changed,
          );
        }
      } else if (localStore != null) {
        final store = localStore!;
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

        if (mirror != null) {
          for (final entry in records.entries) {
            changed.addAll(
              mirror.changedPaths(
                existing[entry.key],
                entry.value,
                syncImageFields,
              ),
            );
          }

          await mirror.refreshNamespace(
            cacheModel,
            syncImageFields,
            prefetchPaths: changed,
          );
        }
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
    final mirror = imageMirror;
    final ctx = await _replicaContext();

    if (ctx != null) {
      final existing = await ctx.replica.store.getById(
        ctx.model.name,
        ctx.scope,
        id,
      );
      final merged = {...?existing, ...json};

      await ctx.replica.ensure(ctx.model.name);
      await ctx.replica.store.upsertAll(ctx.model, ctx.scope, [merged]);

      if (mirror != null) {
        await mirror.refresh(
          ctx.imageNamespace,
          await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
          syncImageFields,
          prefetchPaths: mirror.changedPaths(existing, merged, syncImageFields),
        );
      }

      return;
    }

    final store = localStore;

    if (store == null) {
      return;
    }

    final existing = await store.get(cacheModel, id);
    final merged = {...?existing, ...json};
    await store.put(cacheModel, id, merged);

    if (mirror != null) {
      await mirror.refreshNamespace(
        cacheModel,
        syncImageFields,
        prefetchPaths: mirror.changedPaths(existing, merged, syncImageFields),
      );
    }
  }

  Future<_ReplicaContext?> _replicaContext() async {
    // Resolve the effective path once up front: every offline entry point
    // funnels through here, so [outboxBasePath]/[resolvedBasePath] are correct
    // before any downstream read (enqueue, flush comparison, cache keys).
    await resolvePath();

    final replica = this.replica;
    final model = modelName;

    if (replica == null || model == null) {
      return null;
    }

    final schema = await replica.schema();
    final modelSchema = schema?.models[model];

    if (schema == null || modelSchema == null) {
      return null;
    }

    // The table must exist before any read: a never-synced model (fresh
    // install, dropped database) would otherwise crash the cached reads.
    // Memoized per model, so this is a one-time cost.
    await replica.ensure(model);

    return _ReplicaContext(
      replica: replica,
      schema: schema,
      model: modelSchema,
      scope: replicaScope,
      imageNamespace: '$cacheModel@$replicaScope',
    );
  }

  Set<String> _imagePaths(Iterable<Map<String, dynamic>> records) => {
    for (final record in records)
      for (final field in syncImageFields)
        if (record[field.field] is String &&
            (record[field.field] as String).isNotEmpty)
          record[field.field] as String,
  };

  int _totalPages(int total, int? limit) => limit == null || limit == 0
      ? (total == 0 ? 0 : 1)
      : (total / limit).ceil();

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

class _ReplicaContext {
  final Replica replica;
  final LocalSchema schema;
  final LocalModelSchema model;
  final String scope;
  final String imageNamespace;

  const _ReplicaContext({
    required this.replica,
    required this.schema,
    required this.model,
    required this.scope,
    required this.imageNamespace,
  });
}
