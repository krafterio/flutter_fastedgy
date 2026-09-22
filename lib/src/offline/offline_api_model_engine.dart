/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import '../api/api_helpers.dart';
import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';
import '../api/pagination_result.dart';
import '../api/record_result.dart';
import '../container/container.dart';
import '../logging/logger.dart';
import '../storage/storage_downloader.dart';
import 'image_mirror.dart';
import 'local_image_store.dart';
import 'offline_context_params.dart';
import 'local_schema.dart';
import 'local_sequence.dart';
import 'local_store.dart';
import 'offline_error.dart';
import 'offline_mode.dart';
import 'outbox.dart';
import 'replica.dart';
import 'replica_store.dart';
import 'sync_state.dart';
import 'sync_engine.dart';

/// Offline engine: mirrors an [ApiModel]'s records locally (replicated tables
/// when [ApiModel.modelName] + a [Replica] are available, else a JSON
/// [LocalStore] namespace) so reads work offline and writes buffer for replay.
/// Layered on [ApiModelEngine] (`super.*` are the network calls); the facade
/// only wires it for a synchronizable model.
class OfflineApiModelEngine<T extends BaseModel<T>> extends ApiModelEngine<T> {
  OfflineApiModelEngine(super.owner);

  // Models whose replica is currently unusable (ensure failed), to log the
  // network-only degradation once instead of on every call.
  final Set<String> _replicaFailed = {};

  OfflineStores? get _stores => owner.offlineBindings as OfflineStores?;

  // A replica read/write failing mid-session degrades the single operation
  // (fallback cache or network result kept) instead of failing the caller -
  // a broken local database must never take the app down.
  void _warnReplicaFailure(String operation, Object error) {
    getLogger(
      'OfflineApiModelEngine',
    ).warning('Replica $operation failed for "$cacheModel" - degraded: $error');
  }

  LocalStore? get localStore => !OfflineMode.isEnabled
      ? null
      : _stores?.localStore ??
            (hasService<LocalStore>() ? getService<LocalStore>() : null);

  ImageMirror? get imageMirror {
    if (owner.syncImageFields.isEmpty || !OfflineMode.isEnabled) {
      return null;
    }

    final override = _stores?.imageMirror;

    if (override != null) {
      return override;
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

  Replica? get replica => !OfflineMode.isEnabled
      ? null
      : _stores?.replica ??
            (owner.modelName != null && hasService<Replica>()
                ? getService<Replica>()
                : null);

  Outbox? get outbox => !OfflineMode.isEnabled
      ? null
      : _stores?.outbox ?? (hasService<Outbox>() ? getService<Outbox>() : null);

  String get cacheModel => owner.cacheModel;

  /// Namespace of this resource's records in the local store: [cacheModel],
  /// under the scope of the params its path declares, so two workspaces never
  /// share a cached row. A path declaring none keeps [cacheModel] alone.
  String get _cacheNamespace {
    final scope = hasService<OfflineContextParams>()
        ? getService<OfflineContextParams>().declaredScopeOf(owner.basePath)
        : '';

    return scope.isEmpty ? cacheModel : '$cacheModel@$scope';
  }

  LocalSequence? get sequence => !OfflineMode.isEnabled
      ? null
      : _stores?.sequence ??
            (hasService<LocalSequence>() ? getService<LocalSequence>() : null);

  /// Temporary id of an optimistic offline create: negative, allocated from the
  /// model's own sequence.
  ///
  /// Without a [LocalSequence] there is nowhere to keep a counter, so the
  /// microsecond clock stands in: still negative and still unique, only less
  /// readable.
  Future<int> _nextTempId() async {
    final sequence = this.sequence;

    if (sequence == null) {
      return -DateTime.now().microsecondsSinceEpoch;
    }

    return sequence.nextTempId(cacheModel);
  }

  /// Provisional values for the fields the server fills in on save, so a record
  /// created offline has something to display until its create is replayed
  /// (`DRAFT-{seq}` on a generated reference).
  ///
  /// These live in the local record only — never in the buffered payload, which
  /// stays what the caller asked for. The replay overwrites the record with the
  /// server one, real values included.
  Future<Map<String, dynamic>> _placeholders() async {
    final sequence = this.sequence;

    if (sequence == null) {
      return const {};
    }

    final meta = await owner.metadata();
    final fields = meta?.placeholderFields;

    if (fields == null || fields.isEmpty) {
      return const {};
    }

    final values = <String, dynamic>{};

    for (final field in fields) {
      final seq = await sequence.nextPlaceholder(cacheModel, field.name);
      values[field.name] = field.localPlaceholder!.replaceAll('{seq}', '$seq');
    }

    return values;
  }

  /// Context values captured when an operation is buffered.
  Map<String, String> get outboxContext => hasService<OfflineContextParams>()
      ? getService<OfflineContextParams>().contextFor(owner.basePath)
      : const {};

  // syncFields override, else the model's own fields minus to-many relations.
  Future<List<String>?> _resolveSyncFields() async {
    final override = owner.syncFields;

    if (override != null) {
      return override;
    }

    final meta = await owner.metadata();

    if (meta == null) {
      return null;
    }

    return [
      for (final entry in meta.fields.entries)
        if (entry.value.type != 'one2many' && entry.value.type != 'many2many')
          entry.key,
    ];
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

  /// [ApiModelEngine.get] routes through this one, so overriding it alone covers
  /// both reads.
  @override
  Future<RecordResult<T>> getResult(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    try {
      return RecordResult(
        await _getRemote(id, options: options, params: params),
      );
    } catch (error) {
      if (!_canFallback(error)) {
        rethrow;
      }

      final cached = await cachedGet(id);

      if (cached == null) {
        rethrow;
      }

      return RecordResult(cached, fromCache: true);
    }
  }

  @override
  bool get bufferizesWrites => outbox != null;

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

      if (outbox == null || !isServerUnavailable(error)) {
        rethrow;
      }

      // Optimistic offline create: a negative temporary id marks the record as
      // pending until the outbox replay assigns the real one.
      final tempId = await _nextTempId();
      final record = {
        ...payload.toJson(),
        ...await _placeholders(),
        'id': tempId,
        '_offline_pending': true,
      };
      final cache = await _cacheContext();

      await _mergeRecord(tempId, record);
      await outbox.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: 'POST',
          basePath: owner.resolvedBasePath,
          context: outboxContext,
          model: owner.modelName,
          recordId: tempId,
          payload: payload.toJson(),
          createdAt: createdAt,
          cache: cache,
        ),
      );
      owner.notifyChanged(
        ResourceChangeType.created,
        tempId,
        payload.toJson().keys.toSet(),
      );

      return owner.fromJson(record);
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

      if (outbox == null || !isServerUnavailable(error)) {
        rethrow;
      }

      final cache = await _cacheContext();
      // Base snapshot of the three-way merge: the record as known before the
      // optimistic local write below.
      final base = (await cachedGet(id))?.toJson();

      // A write that changes nothing is not buffered: the replay would send
      // it anyway, in one burst with everything else, for a row the server
      // already holds.
      if (base != null && _changesNothing(payload.toJson(), base)) {
        return owner.fromJson(base);
      }

      await _mergeRecord(id, {
        ...payload.toJson(),
        'id': id,
        '_offline_pending': true,
      });
      await outbox.enqueue(
        (opId, createdAt) => PendingOperation(
          id: opId,
          method: 'PATCH',
          basePath: owner.resolvedBasePath,
          context: outboxContext,
          model: owner.modelName,
          recordId: id,
          payload: payload.toJson(),
          createdAt: createdAt,
          base: base,
          cache: cache,
        ),
      );
      owner.notifyChanged(
        ResourceChangeType.updated,
        id,
        payload.toJson().keys.toSet(),
      );

      final cached = await cachedGet(id);

      return cached ?? owner.fromJson({...payload.toJson(), 'id': id});
    }
  }

  @override
  Future<void> delete(Object id, {ApiParams? params}) async {
    // Resolve the effective path up front: the temp-id branch below reads
    // [resolvedBasePath] without going through the network or _replicaContext.
    await owner.resolvePath();

    // A temporary id never existed server-side: cancel locally without any
    // network call (online or not). If the create already left the queue
    // (replay in flight or done), buffer a delete — the engine resolves the
    // temporary id through its persisted map.
    final temp = id is int && id < 0;

    if (temp && outbox != null) {
      if (!await outbox!.cancelCreateFor(
        owner.resolvedBasePath,
        id,
        context: outboxContext,
      )) {
        final cache = await _cacheContext();

        await outbox!.enqueue(
          (opId, createdAt) => PendingOperation(
            id: opId,
            method: 'DELETE',
            basePath: owner.resolvedBasePath,
            context: outboxContext,
            model: owner.modelName,
            recordId: id,
            createdAt: createdAt,
            cache: cache,
          ),
        );
      }

      owner.notifyChanged(ResourceChangeType.deleted, id);
      await _removeLocal(id);

      return;
    }

    try {
      await super.delete(id, params: params);
    } catch (error) {
      final outbox = this.outbox;

      if (outbox == null || !isServerUnavailable(error)) {
        rethrow;
      }

      // Deleting a record that only exists as a pending offline create cancels
      // both operations.
      if (!await outbox.cancelCreateFor(
        owner.resolvedBasePath,
        id,
        context: outboxContext,
      )) {
        final cache = await _cacheContext();
        final base = (await cachedGet(id))?.toJson();

        await outbox.enqueue(
          (opId, createdAt) => PendingOperation(
            id: opId,
            method: 'DELETE',
            basePath: owner.resolvedBasePath,
            context: outboxContext,
            model: owner.modelName,
            recordId: id,
            createdAt: createdAt,
            base: base,
            cache: cache,
          ),
        );
      }

      owner.notifyChanged(ResourceChangeType.deleted, id);
    }

    await _removeLocal(id);
  }

  @override
  Future<void> sync({ApiParams? params, SyncModelState? state}) async {
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
        getLogger('OfflineApiModelEngine')
            .warning('Outbox flush failed', error);
      }
    }

    // A partially replicated model pre-downloads nothing: the mirror holds
    // whatever the reads happened to return (_listRemote/_getRemote merge each
    // record they receive), so there is no manifest to pull and nothing to
    // prune — a record absent server-side may simply never have been read.
    // Flushing the outbox above is the whole of its sync.
    if ((await owner.metadata())?.isPartiallySynchronizable ?? false) {
      await _refreshMirroredImages(ctx);

      return;
    }

    final pendingByRecord = <String, List<PendingOperation>>{};

    for (final operation in await outbox?.all() ?? const <PendingOperation>[]) {
      if (operation.basePath == owner.resolvedBasePath &&
          sameContext(operation.context, outboxContext) &&
          operation.recordId != null) {
        pendingByRecord
            .putIfAbsent('${operation.recordId}', () => [])
            .add(operation);
      }
    }

    // 1) What the server holds for this model: one light request, or none at
    // all when the caller already asked for every model at once. A mirror with
    // no replica has nowhere to keep a cursor, so it has nothing to compare and
    // does not ask.
    final serverState = ctx == null ? null : state ?? await _serverState();
    final cursor = ctx == null
        ? null
        : await ctx.replica.store.cursor(ctx.model.name, ctx.scope);

    // Nothing moved since the sync that set the cursor: no manifest, no delta.
    if (serverState != null &&
        cursor != null &&
        cursor.updatedAt == serverState.updatedAt &&
        cursor.count == serverState.count) {
      await _refreshMirroredImages(ctx);

      return;
    }

    final localManifest = ctx != null
        ? await ctx.replica.store.manifest(ctx.model, ctx.scope)
        : {
            for (final record in await localStore!.getAll(_cacheNamespace))
              '${record['id']}': record['updated_at'] as String?,
          };
    final records = <Map<String, dynamic>>[];
    var toDelete = <String>[];

    // 2) A mirror that knows where it left off pulls the delta: what was
    // written since, by `updated_at`. The cursor is only ever moved by a
    // completed sync, so the delta cannot skip a record a screen happened to
    // read ahead of it.
    if (serverState != null && cursor?.updatedAt != null) {
      records.addAll(
        await _fetchWhere([
          'updated_at',
          '>=',
          cursor!.updatedAt,
        ], params: params),
      );

      // Deletions leave no trace in a delta: the record count is what gives
      // them away, and the id manifest is only paid for when it disagrees. A
      // buffered create counts locally without existing server-side yet, so it
      // can cost one extra walk until it is replayed.
      final mirrored = localManifest.keys
          .where((id) => !id.startsWith('-'))
          .toSet()
          .union({for (final record in records) '${record['id']}'});

      if (mirrored.length != serverState.count) {
        toDelete = _pruned(
          await _serverIds(params: params),
          localManifest,
          pendingByRecord,
        );
      }

      await _applyPull(
        ctx,
        records,
        toDelete,
        pendingByRecord,
        serverState: serverState,
      );

      return;
    }

    // 3) No cursor (first sync) or no answer from the server (an older one, an
    // unreachable one): the manifest walk, which needs neither.
    final serverManifest = <String, String?>{};
    var offset = 0;

    while (true) {
      final page = await super.list(
        query: ListQuery(
          fields: 'id,updated_at',
          limit: owner.syncPageSize,
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

    final toFetch = <String>[
      for (final entry in serverManifest.entries)
        if (localManifest[entry.key] == null ||
            entry.value == null ||
            localManifest[entry.key] != entry.value)
          entry.key,
    ];
    // Records with buffered writes are never pruned nor clobbered blindly: the
    // outbox replay is the authority on their fate.
    toDelete = _pruned(
      serverManifest.keys.toSet(),
      localManifest,
      pendingByRecord,
    );

    // 4) Batched fetch of the needed records only.
    for (var start = 0; start < toFetch.length; start += owner.syncPageSize) {
      final end = start + owner.syncPageSize > toFetch.length
          ? toFetch.length
          : start + owner.syncPageSize;
      final ids = toFetch
          .sublist(start, end)
          .map((id) => int.tryParse(id) ?? id)
          .toList();
      var chunkOffset = 0;

      while (true) {
        final page = await super.list(
          query: ListQuery(
            fields: await _resolveSyncFields(),
            filter: ['id', 'in', ids],
            limit: owner.syncPageSize,
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

    await _applyPull(
      ctx,
      records,
      toDelete,
      pendingByRecord,
      serverState: serverState,
    );
  }

  /// What the server holds for this model alone.
  ///
  /// Null when it cannot say (a server without the route, an unreachable one):
  /// the caller walks the manifest rather than trusting numbers it does not
  /// have.
  Future<SyncModelState?> _serverState() async {
    // The metadata name is what the route answers to; a model that did not
    // declare one is named after the api name it was read under.
    final name = owner.modelName ?? (await owner.metadata())?.name;

    if (name == null) {
      return null;
    }

    final probe = hasService<SyncStateProbe>()
        ? getService<SyncStateProbe>()
        : SyncStateProbe(fetcher: owner.fetcher);

    return (await probe.fetch(models: [name]))?[name];
  }

  /// Every record matching [rule], paginated with the sync field selection.
  Future<List<Map<String, dynamic>>> _fetchWhere(
    List<Object?> rule, {
    ApiParams? params,
  }) async {
    final records = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      final page = await super.list(
        query: ListQuery(
          fields: await _resolveSyncFields(),
          filter: rule,
          limit: owner.syncPageSize,
          offset: offset,
          orderBy: 'id',
        ),
        params: params,
      );

      for (final item in page.items) {
        if (item.id != null) {
          records.add(item.toJson());
        }
      }

      offset += page.items.length;

      if (page.items.isEmpty || offset >= page.total) {
        break;
      }
    }

    return records;
  }

  /// The ids the server holds, and nothing else: what a delta cannot tell.
  Future<Set<String>> _serverIds({ApiParams? params}) async {
    final ids = <String>{};
    var offset = 0;

    while (true) {
      final page = await super.list(
        query: ListQuery(
          fields: 'id',
          limit: owner.syncPageSize,
          offset: offset,
          orderBy: 'id',
        ),
        params: params,
      );

      for (final item in page.items) {
        if (item.id != null) {
          ids.add('${item.id}');
        }
      }

      offset += page.items.length;

      if (page.items.isEmpty || offset >= page.total) {
        break;
      }
    }

    return ids;
  }

  /// The mirrored records the server no longer holds.
  ///
  /// A record with a buffered write is never pruned: the outbox replay is the
  /// authority on its fate, and an optimistic create (negative id) has no
  /// server-side counterpart to be missing from.
  List<String> _pruned(
    Set<String> serverIds,
    Map<String, String?> localManifest,
    Map<String, List<PendingOperation>> pendingByRecord,
  ) {
    return [
      for (final id in localManifest.keys)
        if (!serverIds.contains(id) &&
            !id.startsWith('-') &&
            !pendingByRecord.containsKey(id))
          id,
    ];
  }

  /// Write a pull to the mirror: records, prunes, the optimistic writes put
  /// back on top, the images, and the cursor the next sync starts from.
  Future<void> _applyPull(
    _ReplicaContext? ctx,
    List<Map<String, dynamic>> records,
    List<String> toDelete,
    Map<String, List<PendingOperation>> pendingByRecord, {
    SyncModelState? serverState,
  }) async {
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
        owner.syncImageFields,
      );

      if (serverState != null) {
        await ctx.replica.store.setCursor(
          ctx.model.name,
          ctx.scope,
          ReplicaCursor(
            updatedAt: serverState.updatedAt,
            count: serverState.count,
          ),
        );
      }

      return;
    }

    final store = localStore!;

    for (final id in toDelete) {
      await store.delete(_cacheNamespace, id);
    }

    await store.putAll(_cacheNamespace, {
      for (final record in records) '${record['id']}': record,
    });
    await _reapplyPending(pendingByRecord);
    await imageMirror?.refreshNamespace(_cacheNamespace, owner.syncImageFields);
  }

  /// Refresh the image mirror against the records already held locally, without
  /// pulling anything new — the image side of a partial sync.
  Future<void> _refreshMirroredImages(_ReplicaContext? ctx) async {
    final mirror = imageMirror;

    if (mirror == null) {
      return;
    }

    if (ctx != null) {
      await mirror.refresh(
        ctx.imageNamespace,
        await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
        owner.syncImageFields,
      );

      return;
    }

    await mirror.refreshNamespace(_cacheNamespace, owner.syncImageFields);
  }

  /// Re-apply the optimistic effect of the still-buffered operations on top of
  /// the freshly pulled records, so a sync never visually reverts an offline
  /// write.
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
              _cacheNamespace,
              operation.recordId!,
            );

            if (current != null) {
              await localStore!.put(_cacheNamespace, operation.recordId!, {
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
            await localStore!.delete(_cacheNamespace, operation.recordId!);
          }
        }
      }
    }
  }

  @override
  Future<List<T>> cachedList() async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      try {
        final records = await ctx.replica.store.getAll(
          ctx.model.name,
          ctx.scope,
        );

        return records.map(owner.fromJson).toList();
      } catch (error) {
        _warnReplicaFailure('cached list read', error);
      }
    }

    final store = localStore;

    if (store == null) {
      return <T>[];
    }

    return (await store.getAll(_cacheNamespace)).map(owner.fromJson).toList();
  }

  @override
  Future<PaginationResult<T>> cachedQuery([ListQuery? query]) async {
    final ctx = await _replicaContext();
    final offset = _queryOffset(query);
    final limit = query?.limit ?? query?.size;

    if (ctx != null) {
      try {
        final result = await ctx.replica.store.query(
          ctx.schema,
          ctx.model.name,
          scope: ctx.scope,
          scopeOf: (_) => ctx.scope,
          filter: query?.filter,
          orderBy: query?.orderBy,
          limit: limit,
          offset: offset > 0 ? offset : null,
        );

        return PaginationResult<T>(
          items: result.records.map(owner.fromJson).toList(),
          total: result.total,
          limit: limit ?? result.total,
          offset: offset,
          totalPages: _totalPages(result.total, limit),
          fromCache: true,
        );
      } catch (error) {
        _warnReplicaFailure('cached query', error);
      }
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
      fromCache: true,
    );
  }

  @override
  Future<T?> cachedGet(Object id) async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      try {
        final record = await ctx.replica.store.getById(
          ctx.model.name,
          ctx.scope,
          id,
        );

        return record == null ? null : owner.fromJson(record);
      } catch (error) {
        _warnReplicaFailure('cached get', error);
      }
    }

    final record = await localStore?.get(_cacheNamespace, id);

    return record == null ? null : owner.fromJson(record);
  }

  @override
  Future<void> clearCache() async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      await ctx.replica.store.clearScope(ctx.model.name, ctx.scope);
      await imageMirror?.refresh(
        ctx.imageNamespace,
        const [],
        owner.syncImageFields,
      );
      return;
    }

    await localStore?.clear(_cacheNamespace);
    await imageMirror?.refreshNamespace(_cacheNamespace, owner.syncImageFields);
  }

  @override
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

  @override
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
      (localStore != null || replica != null) && isServerUnavailable(error);

  Future<PaginationResult<T>?> _offlineListFallback(ListQuery? query) async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      // A filtered query may legitimately match nothing: only rethrow when the
      // scope was never mirrored at all.
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
        try {
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
                mirror.changedPaths(existing, record, owner.syncImageFields),
              );
            }
          }

          await ctx.replica.ensure(ctx.model.name);
          await ctx.replica.store.upsertAll(ctx.model, ctx.scope, merged);

          if (mirror != null) {
            await mirror.refresh(
              ctx.imageNamespace,
              await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
              owner.syncImageFields,
              prefetchPaths: changed,
            );
          }
        } catch (error) {
          _warnReplicaFailure('list mirroring', error);
        }
      } else if (localStore != null) {
        final store = localStore!;
        final existing = {
          for (final record in await store.getAll(_cacheNamespace))
            '${record['id']}': record,
        };
        final records = {
          for (final item in result.items)
            if (item.id != null)
              '${item.id}': {...?existing['${item.id}'], ...item.toJson()},
        };

        await store.putAll(_cacheNamespace, records);

        if (mirror != null) {
          for (final entry in records.entries) {
            changed.addAll(
              mirror.changedPaths(
                existing[entry.key],
                entry.value,
                owner.syncImageFields,
              ),
            );
          }

          await mirror.refreshNamespace(
            _cacheNamespace,
            owner.syncImageFields,
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
    // super.getResult, not super.get: the latter routes back through this
    // engine's override, which would loop.
    final entity = (await super.getResult(
      id,
      options: options,
      params: params,
    )).value;

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
      try {
        final existing = await ctx.replica.store.getById(
          ctx.model.name,
          ctx.scope,
          id,
        );
        final merged = {...?existing, ...json};

        await ctx.replica.ensure(ctx.model.name);
        await ctx.replica.store.upsertAll(ctx.model, ctx.scope, [merged]);

        if (mirror != null) {
          // A record that stopped pointing at a picture may have left it
          // unreferenced: only a pass over the whole namespace can tell, so it
          // is paid then, and not on the reads that add or change nothing.
          if (mirror
              .changedPaths(merged, existing ?? const {}, owner.syncImageFields)
              .isEmpty) {
            await mirror.mergeRecord(
              ctx.imageNamespace,
              existing,
              merged,
              owner.syncImageFields,
            );
          } else {
            await mirror.refresh(
              ctx.imageNamespace,
              await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
              owner.syncImageFields,
              prefetchPaths: mirror.changedPaths(
                existing,
                merged,
                owner.syncImageFields,
              ),
            );
          }
        }
      } catch (error) {
        _warnReplicaFailure('record mirroring', error);
      }

      return;
    }

    final store = localStore;

    if (store == null) {
      return;
    }

    final existing = await store.get(_cacheNamespace, id);
    final merged = {...?existing, ...json};
    await store.put(_cacheNamespace, id, merged);

    if (mirror != null) {
      if (mirror
          .changedPaths(merged, existing ?? const {}, owner.syncImageFields)
          .isEmpty) {
        await mirror.mergeRecord(
          _cacheNamespace,
          existing,
          merged,
          owner.syncImageFields,
        );
      } else {
        await mirror.refreshNamespace(
          _cacheNamespace,
          owner.syncImageFields,
          prefetchPaths: mirror.changedPaths(
            existing,
            merged,
            owner.syncImageFields,
          ),
        );
      }
    }
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

    return OutboxCacheContext(kind: 'json', namespace: _cacheNamespace);
  }

  Future<void> _removeLocal(Object id) async {
    final ctx = await _replicaContext();

    if (ctx != null) {
      try {
        await ctx.replica.store.deleteById(ctx.model.name, ctx.scope, id);
        await imageMirror?.refresh(
          ctx.imageNamespace,
          await ctx.replica.store.getAll(ctx.model.name, ctx.scope),
          owner.syncImageFields,
        );
      } catch (error) {
        _warnReplicaFailure('record removal', error);
      }

      return;
    }

    await localStore?.delete(_cacheNamespace, id);
    await imageMirror?.refreshNamespace(_cacheNamespace, owner.syncImageFields);
  }

  Future<_ReplicaContext?> _replicaContext() async {
    // Resolve the effective path once up front: every offline entry point
    // funnels through here, so [resolvedBasePath] is correct
    // before any downstream read (enqueue, flush comparison, cache keys).
    await owner.resolvePath();

    final replica = this.replica;
    final model = owner.modelName;

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
    //
    // A local database failure must never take the app down: the engine
    // degrades to network-only (as if the model was not replicated) and
    // retries on later calls — the failure may be transient, and ensureModel
    // self-repairs whatever a schema diff can detect.
    try {
      await replica.ensure(model);
      _replicaFailed.remove(model);
    } catch (error) {
      if (_replicaFailed.add(model)) {
        getLogger('OfflineApiModelEngine').warning(
          'Replica unusable for "$model" - degrading to network-only',
          error,
        );
      }

      return null;
    }

    final scope = _replicaScope;

    return _ReplicaContext(
      replica: replica,
      schema: schema,
      model: modelSchema,
      scope: scope,
      imageNamespace: '$cacheModel@$scope',
    );
  }

  String get _replicaScope => hasService<OfflineContextParams>()
      ? getService<OfflineContextParams>().scopeOf(owner.basePath)
      : '';

  /// Whether every value of [payload] is already what the mirror holds. A
  /// to-one relation is compared by id: the payload names one, the record may
  /// hold the whole object.
  bool _changesNothing(
    Map<String, dynamic> payload,
    Map<String, dynamic> record,
  ) => payload.entries.every((entry) {
    final held = record[entry.key];
    final current = held is Map && held.containsKey('id') ? held['id'] : held;

    return jsonEncode(entry.value) == jsonEncode(current);
  });

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

/// Concrete [OfflineBindings]: offline services an [ApiModel] may inject (a
/// test seam); null fields fall back to the container.
class OfflineStores implements OfflineBindings {
  final LocalStore? localStore;
  final ImageMirror? imageMirror;
  final Replica? replica;
  final Outbox? outbox;
  final LocalSequence? sequence;

  const OfflineStores({
    this.localStore,
    this.imageMirror,
    this.replica,
    this.outbox,
    this.sequence,
  });
}

/// Yields the offline engine; registered by `initializeFastEdgy(offline: true)`.
class OfflineApiModelEngineProvider implements ApiModelEngineProvider {
  const OfflineApiModelEngineProvider();

  @override
  ApiModelEngine<T> create<T extends BaseModel<T>>(ApiModel<T> owner) =>
      OfflineApiModelEngine<T>(owner);
}
