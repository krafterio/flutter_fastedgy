/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../bus/events.dart';
import 'local_store.dart';
import 'outbox.dart';

/// An offline update that lost a server-side conflict and is parked for
/// manual resolution instead of being silently dropped.
///
/// Carries everything the UI needs to let the user choose a side, and the
/// engine needs to re-apply that choice: the client's buffered values
/// ([mine]), the server's current record ([server]), the shared [base], and
/// the [fields] the server changed underneath. [cache] and [createdAt] come
/// from the original operation so a "keep mine" resolution can re-enqueue an
/// equivalent write.
class ConflictEntry {
  final String basePath;

  /// Path param values of the originating operation (see
  /// [PendingOperation.context]).
  final Map<String, String> context;

  final Object recordId;
  final Map<String, dynamic> mine;
  final Map<String, dynamic>? base;
  final Map<String, dynamic> server;

  /// The fields the server changed (the ones actually in conflict).
  final List<String> fields;

  final String createdAt;
  final OutboxCacheContext cache;

  const ConflictEntry({
    required this.basePath,
    required this.recordId,
    required this.mine,
    required this.base,
    required this.server,
    required this.fields,
    required this.createdAt,
    required this.cache,
    this.context = const {},
  });

  /// Stable per-record key: a fresh conflict on the same record replaces the
  /// previous one rather than stacking (record ids are server-global, so no
  /// context is needed to disambiguate).
  String get key => '$basePath#$recordId';

  factory ConflictEntry.fromJson(Map<String, dynamic> json) => ConflictEntry(
    basePath: json['base_path'] as String,
    context:
        (json['context'] as Map?)?.map(
          (key, value) => MapEntry('$key', '$value'),
        ) ??
        const {},
    recordId: json['record_id'] as Object,
    mine: (json['mine'] as Map).cast<String, dynamic>(),
    base: (json['base'] as Map?)?.cast<String, dynamic>(),
    server: (json['server'] as Map).cast<String, dynamic>(),
    fields: (json['fields'] as List? ?? const []).cast<String>(),
    createdAt: json['created_at'] as String,
    cache: OutboxCacheContext.fromJson(
      (json['cache'] as Map).cast<String, dynamic>(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'base_path': basePath,
    'context': context,
    'record_id': recordId,
    'mine': mine,
    'base': base,
    'server': server,
    'fields': fields,
    'created_at': createdAt,
    'cache': cache.toJson(),
  };
}

/// Fired when the sync engine parks a conflict for manual resolution.
class OutboxConflictParkedEvent extends Event {
  final ConflictEntry entry;

  const OutboxConflictParkedEvent(this.entry);
}

/// Fired when a parked conflict is resolved — [keptMine] tells which side won
/// (a "keep mine" also re-enqueues an update).
class OutboxConflictResolvedEvent extends Event {
  final String basePath;
  final Object recordId;
  final bool keptMine;

  const OutboxConflictResolvedEvent(
    this.basePath,
    this.recordId, {
    required this.keptMine,
  });
}

/// Persisted set of unresolved conflicts (`_conflicts` namespace of the
/// [LocalStore]), keyed by record so re-conflicts overwrite. Purged with the
/// rest of the cache on logout.
class ConflictStore {
  static const _namespace = '_conflicts';

  final LocalStore _store;

  /// Called with the new conflict count after every mutation — drives
  /// [SyncStatus.conflicts].
  final void Function(int count)? onChanged;

  ConflictStore(this._store, {this.onChanged});

  Future<void> park(ConflictEntry entry) async {
    await _store.put(_namespace, entry.key, entry.toJson());
    await _notifyChanged();
  }

  /// Every parked conflict, newest first (by the original write time).
  Future<List<ConflictEntry>> all() async {
    final entries = (await _store.getAll(
      _namespace,
    )).map(ConflictEntry.fromJson).toList();

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return entries;
  }

  Future<ConflictEntry?> get(String basePath, Object recordId) async {
    final json = await _store.get(_namespace, '$basePath#$recordId');

    return json == null ? null : ConflictEntry.fromJson(json);
  }

  Future<void> resolve(String basePath, Object recordId) async {
    await _store.delete(_namespace, '$basePath#$recordId');
    await _notifyChanged();
  }

  Future<void> _notifyChanged() async {
    final callback = onChanged;

    if (callback != null) {
      callback((await all()).length);
    }
  }
}
