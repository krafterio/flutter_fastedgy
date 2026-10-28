/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
import '../offline/local_store.dart';

/// The last answer of a read, with when it came.
class CachedRead {
  final Object? value;
  final DateTime at;

  const CachedRead(this.value, this.at);

  bool isStale(Duration after) => DateTime.now().difference(at) >= after;
}

/// The last answer of each read kept under a key: in memory for the screen
/// built again, in the local store, when there is one, for the next start.
///
/// The key names what was read for whom: a read of another workspace or
/// account takes a key of its own. [clear] forgets everything, at logout.
class ReadCache {
  static const _namespace = 'read_cache';
  static final _memory = <String, CachedRead>{};

  static LocalStore? get _store =>
      hasService<LocalStore>() ? getService<LocalStore>() : null;

  /// What is kept in memory, without waiting: none before a [read] or a
  /// [write] of this run.
  static CachedRead? peek(String key) => _memory[key];

  static Future<CachedRead?> read(String key) async {
    final kept = _memory[key];

    if (kept != null) {
      return kept;
    }

    try {
      final stored = await _store?.get(_namespace, key);
      final at = stored?['at'];

      if (stored == null || at is! int) {
        return null;
      }

      return _memory[key] = CachedRead(
        stored['value'],
        DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Object? value) async {
    final read = CachedRead(value, DateTime.now());
    _memory[key] = read;

    try {
      await _store?.put(_namespace, key, {
        'value': value,
        'at': read.at.millisecondsSinceEpoch,
      });
    } catch (_) {
      // A store that does not take it leaves the memory alone answering.
    }
  }

  /// The value kept under [key] while fresh, else [fetch]ed and kept: the
  /// one kept, even stale, when the fetch fails.
  static Future<T> through<T>(
    String key,
    Future<T> Function() fetch, {
    Duration staleAfter = const Duration(minutes: 5),
    bool force = false,
  }) async {
    final kept = peek(key) ?? await read(key);
    final value = kept?.value;

    if (!force && kept != null && value is T && !kept.isStale(staleAfter)) {
      return value;
    }

    try {
      final fresh = await fetch();
      await write(key, fresh);

      return fresh;
    } catch (_) {
      if (value is T) {
        return value;
      }

      rethrow;
    }
  }

  static Future<void> clear() async {
    _memory.clear();

    try {
      await _store?.clear(_namespace);
    } catch (_) {
      // Nothing more to forget than the memory.
    }
  }
}
