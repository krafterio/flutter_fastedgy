/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import '../api/api_model.dart';
import '../bus/bus.dart';
import '../fetcher/client.dart';
import '../logging/logger.dart';
import 'local_store.dart';
import 'offline_error.dart';
import 'conflict_store.dart';
import 'outbox.dart';
import 'replica.dart';
import 'sync_status.dart';

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
    this.batchSize = 500,
    this.maxAttempts = 25,
    this.retryBaseDelay = const Duration(seconds: 5),
    this.retryMaxDelay = const Duration(minutes: 5),
  }) : _localStore = localStore,
       _replica = replica,
       _online = online,
       _status = status,
       _conflicts = conflicts;

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

    _status?.setSyncing(true);

    try {
      await _drain(operations);
    } finally {
      _status?.setSyncing(false);
    }
  }

  Future<void> _drain(List<PendingOperation> operations) async {
    final idMap = <String, Object>{};

    // Temp→server mappings persisted by earlier flushes (an operation may
    // reference a temporary id swapped before an app restart).
    if (_localStore != null) {
      for (final entry in await _localStore.getAll(_idMapNamespace)) {
        final temp = entry['temp'];
        final server = entry['server'];

        if (temp != null && server != null) {
          idMap['$temp'] = server as Object;
        }
      }
    }

    final counters = _Counters();
    var index = 0;

    try {
      while (index < operations.length) {
        final operation = operations[index];

        if (operation.method == 'POST') {
          await _replayCreate(operation, idMap, counters);
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
            operations[cursor].basePath == operation.basePath) {
          segment.add(operations[cursor]);
          cursor++;
        }

        await _replayBatch(operation.basePath, segment, idMap, counters);
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
    Map<String, Object> idMap,
    _Counters counters,
  ) async {
    try {
      final response = await _fetcher.post(
        operation.basePath,
        _remapTempIds(operation.payload ?? const {}, idMap) as Map,
      );
      final record = (response.data as Map).cast<String, dynamic>();
      final stillQueued = await _outbox.remove(operation.id);

      if (operation.recordId != null) {
        idMap['${operation.recordId}'] = record['id'] as Object;
        await _localStore?.put(_idMapNamespace, '${operation.recordId}', {
          'temp': operation.recordId,
          'server': record['id'],
        });
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

  Future<void> _replayBatch(
    String basePath,
    List<PendingOperation> segment,
    Map<String, Object> idMap,
    _Counters counters,
  ) async {
    late final List<dynamic> results;

    try {
      final response = await _fetcher.post('$basePath/sync', {
        'operations': [
          for (final operation in segment)
            {
              'op': operation.method == 'DELETE' ? 'delete' : 'update',
              'id': idMap['${operation.recordId}'] ?? operation.recordId,
              'payload': operation.payload == null
                  ? null
                  : _remapTempIds(operation.payload!, idMap),
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
              id: idMap['${operation.recordId}'] ?? operation.recordId,
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
              recordId: idMap['${operation.recordId}'] ?? operation.recordId!,
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
          recordId: entry.recordId,
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
        recordId: serverId,
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

/// Replace offline temporary ids (large negative ints) with their server ids
/// anywhere they appear in a payload: as direct values, inside `{"id": ...}`
/// objects or in lists.
Object? _remapTempIds(Object? value, Map<String, Object> idMap) {
  if (value is int && value < 0) {
    return idMap['$value'] ?? value;
  }

  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: _remapTempIds(entry.value, idMap),
    };
  }

  if (value is List) {
    return [for (final item in value) _remapTempIds(item, idMap)];
  }

  return value;
}
