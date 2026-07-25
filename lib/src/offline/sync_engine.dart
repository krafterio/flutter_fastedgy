/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api/api_model_engine.dart';
import '../bus/bus.dart';
import '../fetcher/client.dart';
import '../metadata/metadata_provider.dart';
import '../metadata/models.dart';
import 'offline_context_params.dart';
import '../logging/logger.dart';
import 'local_store.dart';
import 'offline_error.dart';
import 'conflict_store.dart';
import 'outbox.dart';
import 'pending_upload_store.dart';
import 'replica.dart';
import 'sync_lock.dart';
import 'sync_status.dart';
import 'temp_id_map.dart';

/// Replays the [Outbox] against the server when connectivity comes back.
///
/// Operations are replayed in enqueue order:
/// - **creates** go through their regular POST route one by one (they may
///   carry model-specific semantics); the optimistic temporary record is
///   swapped for the server one and later operations targeting the
///   temporary id are remapped;
/// - **updates/deletes** are batched: consecutive operations sharing a base
///   path are sent in a single `POST {basePath}/sync` request — the server
///   (FastEdgy's sync action) applies them transactionally with a per-field
///   three-way merge against each operation's base snapshot: disjoint
///   fields survive from both writers, overlapping fields are resolved
///   last-writer-wins, an offline delete loses to a fresher server write.
///   Per-operation results heal the local cache ([OutboxOperationMergedEvent]
///   lists partially-applied fields, [OutboxOperationDiscardedEvent] fires
///   for conflicts).
///
/// A connectivity failure stops the flush (the queue is kept for the next
/// attempt); a server rejection discards the operation and fires an
/// [OutboxOperationDiscardedEvent]. Every replayed operation fires the usual
/// [ResourceChangedEvent] so reactive holders refresh.
class SyncEngine {
  final Outbox _outbox;
  final Fetcher _fetcher;
  final Bus _bus;
  final LocalStore? _localStore;
  final Replica? _replica;
  final Stream<bool>? _online;
  final SyncStatus? _status;
  final ConflictStore? _conflicts;
  final SyncLock? _lock;
  final MetadataProvider? _metadatas;
  final PendingUploadStore? _uploads;
  final _logger = getLogger('SyncEngine');

  /// Maximum operations per sync batch (matches the server-side cap).
  final int batchSize;

  /// Attempts after which a repeatedly failing operation is dropped instead
  /// of blocking the queue forever (only enforced on server-side failures —
  /// connectivity failures never discard).
  final int maxAttempts;

  /// Base delay of the deferred retry after a transient server failure
  /// (exponential backoff, capped by [retryMaxDelay]). Connectivity failures
  /// do not schedule a retry: the connectivity stream is their trigger.
  final Duration retryBaseDelay;

  /// Upper bound of the deferred retry delay.
  final Duration retryMaxDelay;

  static const _idMapNamespace = '_outbox_idmap';

  StreamSubscription<bool>? _subscription;
  Future<void>? _running;
  Timer? _retryTimer;
  bool _reflush = false;

  SyncEngine(
    this._outbox,
    this._fetcher,
    this._bus, {
    LocalStore? localStore,
    Replica? replica,
    Stream<bool>? online,
    SyncStatus? status,
    ConflictStore? conflicts,
    SyncLock? lock,
    MetadataProvider? metadatas,
    PendingUploadStore? uploads,
    this.batchSize = 500,
    this.maxAttempts = 25,
    this.retryBaseDelay = const Duration(seconds: 5),
    this.retryMaxDelay = const Duration(minutes: 5),
  }) : _localStore = localStore,
       _replica = replica,
       _online = online,
       _status = status,
       _conflicts = conflicts,
       _lock = lock,
       _metadatas = metadatas,
       _uploads = uploads;

  /// Start listening to connectivity: every regain triggers a flush.
  void start() {
    _subscription ??= _online?.listen((online) {
      _status?.setOnline(online);

      if (online) {
        unawaited(flush());
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Replay the pending operations in order (single flight).
  Future<void> flush() {
    _retryTimer?.cancel();
    _retryTimer = null;

    return _running ??= _flush().whenComplete(() {
      _running = null;

      if (_reflush) {
        _reflush = false;
        unawaited(flush());
      }
    });
  }

  /// Schedule a deferred flush after a transient server failure, with
  /// exponential backoff on the head operation's attempts.
  void _scheduleRetry(int attempts) {
    final exponent = attempts < 1 ? 0 : (attempts > 16 ? 16 : attempts - 1);
    var delay = retryBaseDelay * (1 << exponent);

    if (delay > retryMaxDelay) {
      delay = retryMaxDelay;
    }

    _logger.fine('Retrying the outbox flush in $delay');
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(flush());
    });
  }

  Future<void> _flush() async {
    final operations = await _outbox.all();

    if (operations.isEmpty) {
      return;
    }

    // Another instance is draining the shared outbox: replaying in parallel
    // would send its operations a second time. Retry rather than drop them —
    // the operations enqueued here would otherwise wait for a connectivity
    // event that may never come.
    if (!(await _lock?.tryAcquire() ?? true)) {
      _logger.fine('Outbox replay held by another process, deferring');
      _scheduleRetry(1);

      return;
    }

    _status?.setSyncing(true);

    try {
      await _drain(operations);
    } finally {
      _status?.setSyncing(false);
      await _lock?.release();
    }
  }

  Future<void> _drain(List<PendingOperation> operations) async {
    final idMap = TempIdMap();
    final metadatas = await _resolveMetadatas();

    // Temp→server mappings persisted by earlier flushes (an operation may
    // reference a temporary id swapped before an app restart).
    if (_localStore != null) {
      for (final entry in await _localStore.getAll(_idMapNamespace)) {
        final temp = entry['temp'];
        final server = entry['server'];
        final scope = entry['scope'];

        if (temp != null && server != null && scope != null) {
          idMap.register('$scope', temp as Object, server as Object);
        }
      }
    }

    final counters = _Counters();
    var index = 0;

    try {
      while (index < operations.length) {
        final operation = operations[index];

        if (operation.isUpload) {
          await _replayUpload(operation, idMap, metadatas, counters);
          index++;
          continue;
        }

        if (operation.method == 'POST') {
          await _replayCreate(operation, idMap, metadatas, counters);
          index++;
          continue;
        }

        // Batch the consecutive updates/deletes of the same base path.
        // `index` only advances once the batch went through, so the offline
        // handler below always points at the first non-replayed operation.
        final segment = <PendingOperation>[];
        var cursor = index;

        while (cursor < operations.length &&
            segment.length < batchSize &&
            operations[cursor].method != 'POST' &&
            !operations[cursor].isUpload &&
            operations[cursor].basePath == operation.basePath &&
            sameContext(operations[cursor].context, operation.context)) {
          segment.add(operations[cursor]);
          cursor++;
        }

        await _replayBatch(
          operation.basePath,
          segment,
          idMap,
          metadatas,
          counters,
        );
        index = cursor;
      }
    } on Object catch (error) {
      if (!isOfflineError(error) &&
          !isRetryableServerError(error) &&
          error is! BatchProtocolException) {
        rethrow;
      }

      final pending = operations[index];
      final updated = pending.withAttempts(pending.attempts + 1);

      if (!isOfflineError(error) && updated.attempts >= maxAttempts) {
        // A poison operation must not block the queue forever.
        _logger.warning(
          'Operation ${pending.id} still failing after '
          '${updated.attempts} attempts, dropping it',
        );
        await _discard(pending, 'rejected', error);
        await _outbox.remove(pending.id);
      } else {
        _logger.fine(
          'Transient failure ($error), keeping ${pending.id} for later',
        );
        await _outbox.update(updated);

        if (!isOfflineError(error)) {
          _scheduleRetry(updated.attempts);
        }
      }
    }

    if (counters.replayed > 0 || counters.discarded > 0) {
      _bus.fire(
        OutboxFlushedEvent(
          replayed: counters.replayed,
          discarded: counters.discarded,
        ),
      );
    }
  }

  Future<void> _replayCreate(
    PendingOperation operation,
    TempIdMap idMap,
    Map<String, MetadataModel>? metadatas,
    _Counters counters,
  ) async {
    try {
      final response = await _fetcher.post(
        OfflineContextParams.substituteWith(
          operation.basePath,
          operation.context,
        ),
        idMap.remap(
              operation.payload ?? const {},
              _modelNameOf(operation, metadatas),
              metadatas,
            )
            as Map,
      );
      final record = (response.data as Map).cast<String, dynamic>();
      final stillQueued = await _outbox.remove(operation.id);

      if (operation.recordId != null) {
        final scope = _scopeOf(operation, metadatas);
        idMap.register(scope, operation.recordId!, record['id'] as Object);
        await _localStore?.put(
          _idMapNamespace,
          TempIdMap.key(scope, operation.recordId!),
          {'scope': scope, 'temp': operation.recordId, 'server': record['id']},
        );
        await _cacheDelete(operation.cache, operation.recordId!);
      }

      if (!stillQueued) {
        // The user cancelled this create while its replay was in flight: the
        // record now exists server-side but must not — compensate with a
        // delete replayed right after this flush.
        _logger.fine(
          'Create ${operation.id} cancelled mid-flight, deleting the record',
        );
        await outboxEnqueueCompensatingDelete(
          operation,
          record['id'] as Object,
        );
        _reflush = true;
        counters.replayed++;
        return;
      }

      await _cacheUpsert(operation.cache, record);
      _bus.fire(
        ResourceChangedEvent(
          operation.basePath,
          type: ResourceChangeType.created,
          id: record['id'],
        ),
      );
      counters.replayed++;
    } on Object catch (error) {
      if (isOfflineError(error) || isRetryableServerError(error)) {
        rethrow;
      }

      _logger.warning('Operation ${operation.id} rejected: $error');
      await _discard(operation, 'rejected', error);
      await _outbox.remove(operation.id);
      counters.discarded++;
    }
  }

  /// Send a file buffered while offline, then heal the record that referenced
  /// it locally.
  ///
  /// The buffered blob is only dropped once the server holds the file (or the
  /// operation is definitively rejected): a connectivity failure must leave the
  /// user's file exactly where it was.
  Future<void> _replayUpload(
    PendingOperation operation,
    TempIdMap idMap,
    Map<String, MetadataModel>? metadatas,
    _Counters counters,
  ) async {
    final request = operation.upload;
    final store = _uploads;

    if (request == null || store == null) {
      _logger.warning(
        'Operation ${operation.id} carries no upload, dropping it',
      );
      await _discard(operation, 'rejected');
      await _outbox.remove(operation.id);
      counters.discarded++;

      return;
    }

    final bytes = await store.bytes(request.uploadId);

    if (bytes == null) {
      // The blob is gone (cache cleared, file removed out of band): there is
      // nothing left to send and retrying would never succeed.
      _logger.warning(
        'Buffered file ${request.uploadId} is missing, dropping its upload',
      );
      await _discard(operation, 'rejected');
      await _outbox.remove(operation.id);
      counters.discarded++;

      return;
    }

    try {
      final scope = _scopeOf(operation, metadatas);
      final record = await _sendUpload(
        operation,
        request,
        bytes,
        idMap,
        metadatas,
      );

      await _outbox.remove(operation.id);

      if (record != null) {
        if (operation.recordId != null && record['id'] != null) {
          idMap.register(scope, operation.recordId!, record['id'] as Object);
          await _localStore?.put(
            _idMapNamespace,
            TempIdMap.key(scope, operation.recordId!),
            {
              'scope': scope,
              'temp': operation.recordId,
              'server': record['id'],
            },
          );
          await _cacheDelete(operation.cache, operation.recordId!);
        }

        await _cacheUpsert(operation.cache, record);
      }

      // The server holds the file now, and its rendition is the reference: drop
      // the local copy.
      await store.remove(request.uploadId);

      _bus.fire(
        ResourceChangedEvent(
          operation.basePath,
          type: operation.recordId != null && record?['id'] != null
              ? ResourceChangeType.created
              : ResourceChangeType.updated,
          id: record?['id'] ?? _serverId(operation, idMap, metadatas),
        ),
      );
      counters.replayed++;
    } on Object catch (error) {
      if (isOfflineError(error) || isRetryableServerError(error)) {
        rethrow;
      }

      _logger.warning('Upload ${operation.id} rejected: $error');
      await _discard(operation, 'rejected', error);
      await _outbox.remove(operation.id);
      await store.remove(request.uploadId);
      counters.discarded++;
    }
  }

  /// POST the multipart body and return the record to heal the cache with.
  Future<Map<String, dynamic>?> _sendUpload(
    PendingOperation operation,
    PendingUploadRequest request,
    Uint8List bytes,
    TempIdMap idMap,
    Map<String, MetadataModel>? metadatas,
  ) async {
    final file = MultipartFile.fromBytes(
      bytes,
      filename: request.fileName,
      contentType: request.mimeType == null
          ? null
          : DioMediaType.parse(request.mimeType!),
    );

    if (request.kind == PendingUploadRequest.kindAttachment) {
      final formData = FormData();
      formData.files.add(MapEntry(request.fileName, file));

      // The owner may be a record created offline, so its id is resolved here
      // rather than when the upload was buffered. Generic references are also
      // resolved by shape: the attachment schema may not be mirrored, and a
      // reference names the model it points at, so nothing has to be guessed.
      final meta = idMap.remapReferences(
        idMap.remap(
          request.meta,
          _modelNameOf(operation, metadatas),
          metadatas,
        ),
      );

      if (meta is Map && meta.isNotEmpty) {
        formData.fields.add(MapEntry('meta', jsonEncode(meta)));
      }

      final response = await _fetcher.post(
        '${request.prefix}/storage/upload/attachments',
        formData,
        headers: {'Content-Type': 'multipart/form-data'},
      );
      final attachments =
          (response.data as Map)['attachments'] as List<dynamic>?;

      if (attachments == null || attachments.isEmpty) {
        return null;
      }

      return (attachments.first as Map).cast<String, dynamic>();
    }

    final model = operation.model;
    final id = _serverId(operation, idMap, metadatas);

    if (model == null || id == null || request.field == null) {
      throw StateError(
        'A model field upload needs a model, a record id and a field',
      );
    }

    final response = await _fetcher.post(
      '${request.prefix}/storage/upload/$model/$id/${request.field}',
      FormData.fromMap({'file': file}),
      headers: {'Content-Type': 'multipart/form-data'},
    );
    final path = (response.data as Map)['path'];

    // Heal the field that held the local reference with the stored path.
    return path == null ? null : {'id': id, request.field!: path};
  }

  Future<void> _replayBatch(
    String basePath,
    List<PendingOperation> segment,
    TempIdMap idMap,
    Map<String, MetadataModel>? metadatas,
    _Counters counters,
  ) async {
    late final List<dynamic> results;

    try {
      final path = OfflineContextParams.substituteWith(
        basePath,
        segment.first.context,
      );
      final response = await _fetcher.post('$path/sync', {
        'operations': [
          for (final operation in segment)
            {
              'op': operation.method == 'DELETE' ? 'delete' : 'update',
              'id': _serverId(operation, idMap, metadatas),
              'payload': operation.payload == null
                  ? null
                  : idMap.remap(
                      operation.payload!,
                      _modelNameOf(operation, metadatas),
                      metadatas,
                    ),
              'base': operation.base,
              'created_at': operation.createdAt,
            },
        ],
      });

      results = (response.data as Map)['results'] as List;
    } on Object catch (error) {
      if (isOfflineError(error) || isRetryableServerError(error)) {
        rethrow;
      }

      // The whole batch was rejected (the server MUST expose the sync
      // action): surface every operation and drop them.
      for (final operation in segment) {
        _logger.warning('Operation ${operation.id} rejected: $error');
        await _discard(operation, 'rejected', error);
        await _outbox.remove(operation.id);
        counters.discarded++;
      }

      return;
    }

    if (results.length != segment.length) {
      // Server contract violation: keep the queue rather than losing writes.
      _logger.warning(
        'Sync batch on $basePath returned ${results.length} results '
        'for ${segment.length} operations, retrying later',
      );
      throw BatchProtocolException();
    }

    for (var i = 0; i < segment.length; i++) {
      final operation = segment[i];
      final result = (results[i] as Map).cast<String, dynamic>();
      final record = (result['record'] as Map?)?.cast<String, dynamic>();
      final status = result['status'] as String;

      switch (status) {
        case 'applied' || 'merged':
          if (record != null) {
            await _cacheUpsert(operation.cache, record);
          }

          if (status == 'merged') {
            _bus.fire(
              OutboxOperationMergedEvent(
                operation,
                applied: (result['applied_fields'] as List? ?? const [])
                    .cast<String>(),
                discarded: (result['discarded_fields'] as List? ?? const [])
                    .cast<String>(),
              ),
            );
          }

          _bus.fire(
            ResourceChangedEvent(
              basePath,
              type: operation.method == 'DELETE'
                  ? ResourceChangeType.deleted
                  : ResourceChangeType.updated,
              id: _serverId(operation, idMap, metadatas),
            ),
          );
          counters.replayed++;
        case 'conflict':
          if (record != null) {
            await _cacheUpsert(operation.cache, record);
          }

          // An update that lost is parked for manual resolution instead of
          // being dropped (delete-losses and payload-less ops have nothing to
          // reconcile — those still discard).
          if (_conflicts != null &&
              operation.method != 'DELETE' &&
              operation.payload != null &&
              record != null) {
            final entry = ConflictEntry(
              basePath: basePath,
              context: operation.context,
              recordId:
                  _serverId(operation, idMap, metadatas) ?? operation.recordId!,
              mine: operation.payload!,
              base: operation.base,
              server: record,
              fields: (result['discarded_fields'] as List? ?? const [])
                  .cast<String>(),
              createdAt: operation.createdAt,
              cache: operation.cache,
            );
            await _conflicts.park(entry);
            _bus.fire(OutboxConflictParkedEvent(entry));
          } else {
            await _discard(operation, 'conflict');
          }

          counters.discarded++;
        case 'deleted':
          if (operation.recordId != null) {
            await _cacheDelete(operation.cache, operation.recordId!);
          }

          await _discard(operation, 'conflict');
          counters.discarded++;
        case 'rejected':
          _logger.warning(
            'Operation ${operation.id} rejected by the server: '
            '${result['detail']}',
          );
          await _discard(operation, 'rejected');
          counters.discarded++;
        default:
          await _discard(operation, 'rejected');
          counters.discarded++;
      }

      await _outbox.remove(operation.id);
    }
  }

  /// Resolve a parked [ConflictEntry], keeping either side wholesale.
  ///
  /// [keepMine] re-enqueues the buffered write with the server record as its
  /// base, so the client values win the next flush's last-writer-wins;
  /// otherwise the local cache already holds the server record and the entry
  /// is simply dropped.
  Future<void> resolveConflict(
    ConflictEntry entry, {
    required bool keepMine,
  }) async {
    if (keepMine) {
      await _outbox.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: 'PATCH',
          basePath: entry.basePath,
          context: entry.context,
          recordId: entry.recordId,
          model: entry.cache.model,
          payload: entry.mine,
          base: entry.server,
          createdAt: createdAt,
          cache: entry.cache,
        ),
      );
    }

    await _conflicts?.resolve(entry.basePath, entry.recordId);
    _bus.fire(
      OutboxConflictResolvedEvent(
        entry.basePath,
        entry.recordId,
        keptMine: keepMine,
      ),
    );

    if (keepMine) {
      unawaited(flush());
    }
  }

  /// Enqueue the delete compensating a create cancelled mid-replay.
  Future<void> outboxEnqueueCompensatingDelete(
    PendingOperation operation,
    Object serverId,
  ) {
    return _outbox.enqueue(
      (id, createdAt) => PendingOperation(
        id: id,
        method: 'DELETE',
        basePath: operation.basePath,
        context: operation.context,
        recordId: serverId,
        model: operation.model,
        createdAt: createdAt,
        cache: operation.cache,
      ),
    );
  }

  Future<void> _discard(
    PendingOperation operation,
    String reason, [
    Object? error,
  ]) async {
    if (operation.method == 'POST' && operation.recordId != null) {
      // The optimistic temporary record never got a server identity.
      await _cacheDelete(operation.cache, operation.recordId!);
    }

    _bus.fire(OutboxOperationDiscardedEvent(operation, reason, error));
  }

  Future<void> _cacheUpsert(
    OutboxCacheContext cache,
    Map<String, dynamic> record,
  ) async {
    if (record['id'] == null) {
      return;
    }

    if (cache.kind == 'replica') {
      final schema = await _replica?.schema();
      final model = schema?.models[cache.model];

      if (_replica != null && model != null) {
        await _replica.ensure(model.name);
        await _replica.store.upsertAll(model, cache.scope, [record]);
      }

      return;
    }

    await _localStore?.put(cache.namespace, record['id'] as Object, record);
  }

  // Metadata resolve the target model of each payload field, so a temporary id
  // is only substituted within the model it was allocated for. Absent provider
  // (or metadata not fetched yet): no field can be resolved, so no substitution
  // happens rather than a wrong one.
  Future<Map<String, MetadataModel>?> _resolveMetadatas() async {
    final provider = _metadatas;

    if (provider == null) {
      return null;
    }

    try {
      return await provider.getMetadatas();
    } on Object catch (error) {
      _logger.fine('Metadata unavailable for the id remapping: $error');

      return null;
    }
  }

  /// The id an operation targets server-side: its temporary id swapped for the
  /// real one once its create was replayed.
  Object? _serverId(
    PendingOperation operation,
    TempIdMap idMap,
    Map<String, MetadataModel>? metadatas,
  ) {
    final recordId = operation.recordId;

    if (recordId == null) {
      return null;
    }

    return idMap.resolve(_scopeOf(operation, metadatas), recordId) ?? recordId;
  }

  String _scopeOf(
    PendingOperation operation,
    Map<String, MetadataModel>? metadatas,
  ) => TempIdMap.scopeOf(
    operation.model,
    operation.basePath,
    metadatas,
    fallback: operation.cache.namespace,
  );

  String? _modelNameOf(
    PendingOperation operation,
    Map<String, MetadataModel>? metadatas,
  ) =>
      operation.model ??
      (metadatas == null ? null : _scopeOf(operation, metadatas));

  Future<void> _cacheDelete(OutboxCacheContext cache, Object id) async {
    if (cache.kind == 'replica') {
      if (cache.model != null) {
        await _replica?.store.deleteById(cache.model!, cache.scope, id);
      }

      return;
    }

    await _localStore?.delete(cache.namespace, id);
  }
}

class _Counters {
  var replayed = 0;
  var discarded = 0;
}

/// The sync endpoint broke the one-result-per-operation contract.
class BatchProtocolException implements Exception {}
