/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Where a list keeps its state: the query of the location shown, each of its
/// keys after [prefix], so that two lists of one screen keep theirs apart.
///
/// It tells its listeners when the keys of the list change from outside (the
/// back button of a browser, a link followed), and when its own writes land.
abstract class ListUrl implements Listenable {
  /// The query of the router shown in [context]: read there, written by
  /// replacing the location, never by pushing one, and only while the route
  /// it was made on is the one shown.
  factory ListUrl.router(BuildContext context, {String prefix = ''}) {
    final state = GoRouterState.of(context);

    return _RouterUrl(
      GoRouter.of(context),
      state.fullPath,
      prefix,
      state.uri.queryParameters,
    );
  }

  /// A query held in memory, see [MemoryListUrl].
  factory ListUrl.memory({
    Map<String, String> initial = const {},
    String prefix = '',
  }) => MemoryListUrl(initial: initial, prefix: prefix);

  /// What comes before each key of the list.
  String get prefix;

  /// The keys of the list, without their prefix.
  Map<String, String> read();

  /// Writes keys of the list, a null or empty value removing its key. The
  /// writes of one turn, those of every list of the location and of the
  /// screen, land together.
  void write(Map<String, String?> patch);

  /// The same query, the keys of another list after [prefix].
  ListUrl withPrefix(String prefix);
}

final _pending = Expando<Map<String, String?>>();

/// Queues [patch] on [location] with what the other lists of the location
/// write in the same turn, then [flush]es it all at once.
void _queue(
  Object location,
  Map<String, String?> patch,
  void Function(Map<String, String?> patch) flush,
) {
  final pending = _pending[location];

  if (pending != null) {
    pending.addAll(patch);

    return;
  }

  final queued = {...patch};

  _pending[location] = queued;
  scheduleMicrotask(() {
    _pending[location] = null;
    flush(queued);
  });
}

Map<String, String> _patched(
  Map<String, String> query,
  Map<String, String?> patch,
) {
  final next = {...query};

  patch.forEach((key, value) {
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
  });

  return next;
}

abstract class _KeysUrl implements ListUrl {
  _KeysUrl(this.prefix);

  @override
  final String prefix;

  final _listeners = <VoidCallback>[];
  Map<String, String> _last = const {};

  /// What tells a location changed.
  Listenable get _source;

  /// What identifies the location for the queue of its writes.
  Object get _location;

  /// The query of the location, while the one of this list is shown.
  Map<String, String>? get _query;

  void _flush(Map<String, String?> patch);

  Map<String, String> _keysOf(Map<String, String> query) => {
    for (final MapEntry(:key, :value) in query.entries)
      if (key.startsWith(prefix)) key.substring(prefix.length): value,
  };

  @override
  Map<String, String> read() {
    final query = _query;

    return query == null ? _last : _keysOf(query);
  }

  /// Takes what the location says now as already told.
  void _see() => _last = read();

  @override
  void write(Map<String, String?> patch) => _queue(_location, {
    for (final MapEntry(:key, :value) in patch.entries) '$prefix$key': value,
  }, _flush);

  void _changed() {
    final query = _query;

    if (query == null) {
      return;
    }

    final keys = _keysOf(query);

    if (mapEquals(keys, _last)) {
      return;
    }

    _last = keys;

    for (final listener in [..._listeners]) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      _see();
      _source.addListener(_changed);
    }

    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_listeners.remove(listener) && _listeners.isEmpty) {
      _source.removeListener(_changed);
    }
  }
}

class _RouterUrl extends _KeysUrl {
  _RouterUrl(this._router, this._route, super.prefix, this._entry) {
    _last = _keysOf(_entry);
  }

  final GoRouter _router;

  /// The query of the route when the list was made on it, which may be
  /// covered by another one.
  final Map<String, String> _entry;

  /// The route the list is drawn on, `/w/:workspace/tasks`: the location
  /// another workspace shows is still the list's.
  final String? _route;

  @override
  Listenable get _source => _router.routerDelegate;

  @override
  Object get _location => _router;

  bool get _shown => _router.state.fullPath == _route;

  @override
  Map<String, String>? get _query =>
      _shown ? _router.state.uri.queryParameters : null;

  @override
  void _flush(Map<String, String?> patch) {
    if (!_shown) {
      return;
    }

    final uri = _router.state.uri;
    final query = _patched(uri.queryParameters, patch);

    if (mapEquals(query, uri.queryParameters)) {
      return;
    }

    unawaited(
      _router.replace(
        Uri(
          path: uri.path,
          queryParameters: query.isEmpty ? null : query,
        ).toString(),
      ),
    );
  }

  @override
  ListUrl withPrefix(String prefix) =>
      _RouterUrl(_router, _route, prefix, _query ?? _entry);
}

class _MemoryQuery extends ChangeNotifier {
  _MemoryQuery(this._query);

  Map<String, String> _query;

  Map<String, String> get query => _query;

  set query(Map<String, String> value) {
    _query = value;
    notifyListeners();
  }
}

/// A query held in memory, for a list whose state must not survive the
/// screen, and for tests: [go] changes it as a navigation would.
class MemoryListUrl extends _KeysUrl {
  MemoryListUrl({Map<String, String> initial = const {}, String prefix = ''})
    : this._(_MemoryQuery({...initial}), prefix);

  MemoryListUrl._(this._memory, String prefix) : super(prefix) {
    _see();
  }

  final _MemoryQuery _memory;

  /// The whole query, the keys of every list included.
  Map<String, String> get query => Map.unmodifiable(_memory.query);

  /// Replaces the whole query, from outside the lists.
  void go(Map<String, String> query) {
    _memory.query = {...query};
  }

  @override
  Listenable get _source => _memory;

  @override
  Object get _location => _memory;

  @override
  Map<String, String> get _query => _memory.query;

  @override
  void _flush(Map<String, String?> patch) => go(_patched(_memory.query, patch));

  @override
  ListUrl withPrefix(String prefix) => MemoryListUrl._(_memory, prefix);
}
