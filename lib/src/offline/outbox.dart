/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../bus/events.dart';
import 'local_store.dart';

/// Storage context of a pending operation, letting the sync engine reconcile
/// the local cache after a replay without knowing the API classes.
class OutboxCacheContext {
  /// 'replica' or 'json'.
  final String kind;

  /// JSON namespace ([kind] 'json') or image/index namespace.
  final String namespace;

  /// Replicated model name ([kind] 'replica').
  final String? model;

  /// Replica scope ([kind] 'replica').
  final String scope;

  const OutboxCacheContext({
    required this.kind,
    required this.namespace,
    this.model,
    this.scope = '',
  });

  factory OutboxCacheContext.fromJson(Map<String, dynamic> json) =>
      OutboxCacheContext(
        kind: json['kind'] as String,
        namespace: json['namespace'] as String,
        model: json['model'] as String?,
        scope: json['scope'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'namespace': namespace,
    'model': model,
    'scope': scope,
  };
}

/// Shallow equality of two operation contexts.
bool sameContext(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

/// The multipart upload of a [PendingOperation] whose method is `UPLOAD`.
///
/// The bytes themselves live in the `PendingUploadStore` under [uploadId]; this
/// only describes where to send them.
class PendingUploadRequest {
  /// `attachment` — one file becoming an Attachment record through
  /// `/storage/upload/attachments`, its values (owner included) carried by
  /// [meta] so the record is created already associated;
  /// `modelField` — one file written to a model's field through
  /// `/storage/upload/{model}/{id}/{field}`.
  final String kind;

  /// Handle of the buffered bytes in the `PendingUploadStore`.
  final String uploadId;

  final String fileName;
  final String? mimeType;

  /// Attachment values applied server-side (`kind` `attachment`); ids inside are
  /// remapped on replay, so it may reference a record created offline.
  final Map<String, dynamic>? meta;

  /// Target field (`kind` `modelField`).
  final String? field;

  /// Storage route prefix captured when the upload was buffered.
  final String prefix;

  static const kindAttachment = 'attachment';
  static const kindModelField = 'modelField';

  const PendingUploadRequest({
    required this.kind,
    required this.uploadId,
    required this.fileName,
    this.mimeType,
    this.meta,
    this.field,
    this.prefix = '',
  });

  factory PendingUploadRequest.fromJson(Map<String, dynamic> json) =>
      PendingUploadRequest(
        kind: json['kind'] as String,
        uploadId: json['upload_id'] as String,
        fileName: json['file_name'] as String,
        mimeType: json['mime_type'] as String?,
        meta: (json['meta'] as Map?)?.cast<String, dynamic>(),
        field: json['field'] as String?,
        prefix: json['prefix'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'upload_id': uploadId,
    'file_name': fileName,
    'mime_type': mimeType,
    'meta': meta,
    'field': field,
    'prefix': prefix,
  };
}

/// A buffered offline write, replayed in order by the sync engine.
class PendingOperation {
  final String id;

  /// 'POST', 'PATCH', 'DELETE' or 'UPLOAD'.
  final String method;

  /// Base path of the resource, unresolved (e.g. '/{workspace}/users').
  final String basePath;

  /// Path param values captured at enqueue time — the replay resolves
  /// [basePath] with them, not with the current context (a workspace switch
  /// must not reroute buffered writes).
  final Map<String, String> context;

  /// Target record id (the optimistic temporary id for creates).
  final Object? recordId;

  /// Metadata name of the model this operation targets, when known.
  ///
  /// Temporary ids are allocated per model, so two models legitimately hand out
  /// the same values: resolving one back to its server id needs the model it
  /// belongs to, not only its value. Falls back to the cache namespace, unique
  /// per resource, for a model whose name is unknown.
  final String? model;

  final Map<String, dynamic>? payload;

  /// Enqueue time (ISO) — the client side of the last-writer-wins
  /// comparison.
  final String createdAt;

  /// Snapshot of the record as known by the client at enqueue time — the
  /// base of the three-way field merge on replay (null when the client had
  /// never seen the record).
  final Map<String, dynamic>? base;

  final int attempts;
  final OutboxCacheContext cache;

  /// The multipart upload to replay, when [method] is `UPLOAD`.
  final PendingUploadRequest? upload;

  const PendingOperation({
    required this.id,
    required this.method,
    required this.basePath,
    required this.cache,
    required this.createdAt,
    this.context = const {},
    this.recordId,
    this.model,
    this.payload,
    this.base,
    this.attempts = 0,
    this.upload,
  });

  static const methodUpload = 'UPLOAD';

  bool get isUpload => method == methodUpload;

  factory PendingOperation.fromJson(Map<String, dynamic> json) =>
      PendingOperation(
        id: json['id'] as String,
        method: json['method'] as String,
        basePath: json['base_path'] as String,
        context:
            (json['context'] as Map?)?.map(
              (key, value) => MapEntry('$key', '$value'),
            ) ??
            const {},
        recordId: json['record_id'],
        model: json['model'] as String?,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
        createdAt: json['created_at'] as String,
        base: (json['base'] as Map?)?.cast<String, dynamic>(),
        attempts: json['attempts'] as int? ?? 0,
        cache: OutboxCacheContext.fromJson(
          (json['cache'] as Map).cast<String, dynamic>(),
        ),
        upload: json['upload'] == null
            ? null
            : PendingUploadRequest.fromJson(
                (json['upload'] as Map).cast<String, dynamic>(),
              ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'base_path': basePath,
    'context': context,
    'record_id': recordId,
    'model': model,
    'payload': payload,
    'created_at': createdAt,
    'base': base,
    'attempts': attempts,
    'cache': cache.toJson(),
    'upload': upload?.toJson(),
  };

  PendingOperation withAttempts(int attempts) => PendingOperation(
    id: id,
    method: method,
    basePath: basePath,
    context: context,
    recordId: recordId,
    model: model,
    payload: payload,
    createdAt: createdAt,
    base: base,
    attempts: attempts,
    cache: cache,
    upload: upload,
  );
}

/// Fired when the sync engine discards a pending operation (server
/// rejection, or a newer server version winning the last-write-wins
/// resolution).
class OutboxOperationDiscardedEvent extends Event {
  final PendingOperation operation;

  /// 'rejected' or 'conflict'.
  final String reason;

  final Object? error;

  const OutboxOperationDiscardedEvent(
    this.operation,
    this.reason, [
    this.error,
  ]);
}

/// Fired when the three-way merge of a replayed update kept only part of
/// the buffered fields (the others were won by a fresher server write).
class OutboxOperationMergedEvent extends Event {
  final PendingOperation operation;

  /// Fields of the buffered payload that were applied.
  final List<String> applied;

  /// Fields dropped because the server write was the last one.
  final List<String> discarded;

  const OutboxOperationMergedEvent(
    this.operation, {
    required this.applied,
    required this.discarded,
  });
}

/// Fired after a flush drained the outbox (some operations may have been
/// discarded — see [OutboxOperationDiscardedEvent]).
class OutboxFlushedEvent extends Event {
  final int replayed;
  final int discarded;

  const OutboxFlushedEvent({required this.replayed, required this.discarded});
}

/// Persisted FIFO of offline writes, stored in the [LocalStore] (`_outbox`
/// namespace) — outside the replica tables so it survives their rebuilds,
/// and purged with the rest of the cache on logout.
class Outbox {
  static const _namespace = '_outbox';

  final LocalStore _store;
  var _sequence = 0;

  /// Called with the new pending count after every queue mutation (enqueue,
  /// remove, update) — the single hook driving [SyncStatus.pending].
  final void Function(int pending)? onChanged;

  Outbox(this._store, {this.onChanged});

  /// Enqueue [operation] built by [build] with a fresh monotonic id.
  Future<PendingOperation> enqueue(
    PendingOperation Function(String id, String createdAt) build,
  ) async {
    final now = DateTime.now();
    final id =
        '${now.microsecondsSinceEpoch.toString().padLeft(20, '0')}'
        '-${(_sequence++).toString().padLeft(4, '0')}';
    final operation = build(id, now.toIso8601String());

    await _store.put(_namespace, operation.id, operation.toJson());
    await _notifyChanged();

    return operation;
  }

  /// Every pending operation, in enqueue order.
  Future<List<PendingOperation>> all() async {
    final operations = (await _store.getAll(
      _namespace,
    )).map(PendingOperation.fromJson).toList();

    operations.sort((a, b) => a.id.compareTo(b.id));

    return operations;
  }

  /// Remove [id] from the queue; returns false when the operation was
  /// already gone (e.g. cancelled while its replay was in flight).
  Future<bool> remove(String id) async {
    final existing = await _store.get(_namespace, id);

    if (existing == null) {
      return false;
    }

    await _store.delete(_namespace, id);
    await _notifyChanged();

    return true;
  }

  Future<void> update(PendingOperation operation) async {
    await _store.put(_namespace, operation.id, operation.toJson());
    await _notifyChanged();
  }

  Future<void> _notifyChanged() async {
    final callback = onChanged;

    if (callback != null) {
      callback((await all()).length);
    }
  }

  /// Deleting a record that only exists as a pending offline create cancels
  /// both operations; returns true when the pair was cancelled.
  Future<bool> cancelCreateFor(
    String basePath,
    Object recordId, {
    Map<String, String> context = const {},
  }) async {
    for (final operation in await all()) {
      if (operation.method == 'POST' &&
          operation.basePath == basePath &&
          sameContext(operation.context, context) &&
          '${operation.recordId}' == '$recordId') {
        await remove(operation.id);

        return true;
      }
    }

    return false;
  }
}
