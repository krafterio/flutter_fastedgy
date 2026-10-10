/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/api_model.dart';
import '../realtime/resource_watch.dart';
import 'data_groups.dart';
import 'data_iterator.dart';

/// The list a record is opened from, to add to the query of the route of the
/// record so that a reload keeps it: the filter the list sends, the one of
/// the [group] it is opened from, and its order.
Map<String, String> listContext(
  DataIterator<dynamic> list, {
  DataGroup<dynamic>? group,
}) {
  final filter = group != null ? group.filter : list.combinedFilter;
  final orderBy = list.orderBy;

  return {
    'ctx': jsonEncode({
      'f': ?filter,
      if (orderBy != null && orderBy.isNotEmpty) 'o': orderBy,
    }),
  };
}

/// Where the neighbours of a record stand.
enum SiblingsStatus { idle, loading, success, error }

/// The records before and after the one a route shows, in the list it was
/// opened from, the port of `useRecordContext`. The server computes them on
/// the query of that list, carried by the route ([listContext]), so they hold
/// after a reload; [go] replaces the location, so going back returns to the
/// list rather than to each record seen.
///
/// The neighbours are read again when the record changes in the route, and
/// when its model changes (realtime); an answer landing after a newer one is
/// dropped.
class RecordContext extends ChangeNotifier {
  /// The context of the record the route of [context] shows, its id under
  /// [param].
  RecordContext.router(
    BuildContext context,
    this.api, {
    this.param = 'id',
    this.refreshDelay = const Duration(milliseconds: 250),
  }) : _router = GoRouter.of(context),
       _route = GoRouterState.of(context).fullPath {
    final state = GoRouterState.of(context);

    _id = state.pathParameters[param];
    _ctx = state.uri.queryParameters['ctx'];
    _router.routerDelegate.addListener(_onRoute);
    _watch = watchResource(
      api,
      (_) => _onChanged(),
      refreshDelay: Duration.zero,
    );
    unawaited(_read(false));
  }

  final ApiModel<dynamic> api;

  /// The parameter of the route holding the id.
  final String param;

  /// How long a burst of changes waits before the neighbours are read again.
  final Duration refreshDelay;

  final GoRouter _router;
  final String? _route;
  late final ResourceWatch _watch;

  String? _id;
  String? _ctx;
  Object? _previous;
  Object? _next;
  SiblingsStatus _status = SiblingsStatus.idle;
  Object? _error;
  int _generation = 0;
  Timer? _timer;
  bool _disposed = false;

  Object? get previous => _previous;

  Object? get next => _next;

  SiblingsStatus get status => _status;

  Object? get error => _error;

  /// The list the record was opened from, as the route carries it.
  ({Object? filter, List<String>? orderBy})? get _list {
    final raw = _ctx;

    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final read = jsonDecode(raw);

      return read is Map
          ? (
              filter: read['f'],
              orderBy: (read['o'] as List?)?.map((term) => '$term').toList(),
            )
          : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether the record was opened from a list.
  bool get inList => _list != null;

  /// Shows the record [id] in place of this one, the query kept.
  void go(Object id) {
    final state = _router.state;
    final params = {...state.pathParameters, param: '$id'};
    final path = (_route ?? state.uri.path).replaceAllMapped(
      RegExp(r':(\w+)(\([^)]*\))?'),
      (match) => Uri.encodeComponent(params[match[1]] ?? ''),
    );

    unawaited(
      _router.replace(
        Uri(
          path: path,
          queryParameters: state.uri.queryParameters.isEmpty
              ? null
              : state.uri.queryParameters,
        ).toString(),
      ),
    );
  }

  /// Reads the neighbours again.
  Future<void> refresh() => _read(false);

  void _onRoute() {
    final state = _router.state;

    if (state.fullPath != _route) {
      return;
    }

    final id = state.pathParameters[param];
    final ctx = state.uri.queryParameters['ctx'];

    if (id != _id || ctx != _ctx) {
      _id = id;
      _ctx = ctx;
      unawaited(_read(false));
    }
  }

  void _onChanged() {
    if (_status == SiblingsStatus.idle) {
      return;
    }

    _timer?.cancel();
    _timer = Timer(refreshDelay, () => unawaited(_read(true)));
  }

  Future<void> _read(bool quiet) async {
    final id = _id;
    final list = _list;
    final asked = ++_generation;

    if (id == null || list == null) {
      _previous = null;
      _next = null;
      _status = SiblingsStatus.idle;
      _notify();

      return;
    }

    if (!quiet) {
      _status = SiblingsStatus.loading;
      _notify();
    }

    try {
      final siblings = await api.siblings(
        id,
        filter: list.filter,
        orderBy: list.orderBy,
      );

      // Stepping fast outruns the server: only the last id asked answers.
      if (asked != _generation) {
        return;
      }

      _previous = siblings.previous;
      _next = siblings.next;
      _error = null;
      _status = SiblingsStatus.success;
    } catch (failure) {
      if (quiet || asked != _generation) {
        return;
      }

      _previous = null;
      _next = null;
      _error = failure;
      _status = SiblingsStatus.error;
    }

    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _watch.cancel();
    _router.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }
}
