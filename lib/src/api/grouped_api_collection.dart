/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import 'api_collection.dart';
import 'api_model.dart';
import 'base_model.dart';
import 'data_availability.dart';
import 'group_source.dart';
import 'list_sort.dart';

/// One bucket of a [GroupedApiCollection]: its header, and the rows it holds.
class GroupedEntry<T extends BaseModel<T>> {
  final ListGroup group;

  /// A real [ApiCollection] filtered to this bucket — so its rows, its exact
  /// [ApiCollection.total], its pagination, its loading and its availability
  /// verdicts are the ordinary ones, and any widget already bound to a
  /// collection works on a bucket unchanged.
  final ApiCollection<T> collection;

  const GroupedEntry(this.group, this.collection);
}

/// A list read one bucket at a time: the axis says which buckets exist (see
/// [GroupSource]) and each bucket is a request of its own.
///
/// That is the price of a server with no `group_by`, and what it buys is what
/// makes a grouped list usable: every bucket knows exactly how many rows it
/// holds and pages through them without touching its neighbours.
///
/// One page of buckets costs one request for the axis (none for a `choice` one)
/// plus one per bucket. Mutations do **not** multiply that: this holds the only
/// bus subscription, a delete costs nothing, and a burst of writes collapses
/// into a single refresh.
class GroupedApiCollection<T extends BaseModel<T>> extends ChangeNotifier
    with DataAvailabilityState<T> {
  GroupedApiCollection(
    this.api,
    this.source, {
    dynamic fields,
    dynamic orderBy,
    Object? filter,
    ListSort sort = ListSort.empty,
    this.rowLimit = 20,
    this.refreshDelay = const Duration(milliseconds: 250),
  }) : _fields = fields,
       // An ordering known up front — restored from a URL — is what the buckets
       // are built with, rather than re-read right after their first page.
       _orderBy = sort.isEmpty ? orderBy : sort.toOrderBy(),
       _sort = sort,
       _filter = filter {
    _sub = getService<Bus>().on<ResourceChangedEvent>().listen(
      _onResourceChanged,
    );
    listenAvailability();
  }

  static const Object _unset = Object();

  @override
  final ApiModel<T> api;

  /// The axis: which buckets exist, one page at a time.
  final GroupSource source;

  /// Rows per page **inside** each bucket.
  final int rowLimit;

  /// How long a burst of mutations is collapsed before the buckets re-read.
  final Duration refreshDelay;

  dynamic _fields;
  dynamic _orderBy;
  Object? _filter;
  ListSort _sort;

  List<GroupedEntry<T>> _entries = [];
  bool _loaded = false;
  bool _isLoading = false;
  bool _disposed = false;
  bool _notifyScheduled = false;
  int _batch = 0;
  bool _batchNotify = false;
  Timer? _refresh;
  Timer? _axisRefresh;
  late final StreamSubscription<ResourceChangedEvent> _sub;

  List<GroupedEntry<T>> get entries => _entries;

  bool get isLoaded => _loaded;

  /// True while the axis and the first read of its buckets are in flight — the
  /// whole-list loading state. A bucket loading a further page reports it on
  /// its own collection.
  bool get isLoading => _isLoading;

  int get groupPage => source.page;
  int get groupTotal => source.total;
  int get groupTotalPages => source.totalPages;
  bool get isGroupTotalExact => source.isTotalExact;
  bool get hasNextGroupPage => source.hasNextPage;
  bool get hasPreviousGroupPage => source.hasPreviousPage;

  /// Ordering applied inside every bucket.
  ListSort get sort => _sort;

  Object? get filter => _filter;

  /// Rows across the buckets of the current page.
  int get rowCount {
    var count = 0;

    for (final entry in _entries) {
      count += entry.collection.items.length;
    }

    return count;
  }

  @override
  bool get hasData {
    for (final entry in _entries) {
      if (entry.collection.hasData) {
        return true;
      }
    }

    return false;
  }

  /// True when the read settled with nothing to show anywhere — an honest empty
  /// state, unlike [requiresConnection].
  bool get isEmpty =>
      !hasData &&
      (availability == DataAvailability.live ||
          availability == DataAvailability.cached);

  @override
  void notifyAvailability() => _scheduleNotify();

  Future<bool> load() async {
    _loaded = true;
    _isLoading = true;
    beginRead();
    // Now, outside the batch: the skeleton has to appear before the fan-out,
    // not after it.
    _flushNotify();

    return _batched(() async {
      // Resolved once, before the fan-out: an ApiModel memoizes its path and
      // its engine only *after* awaiting the metadata, so N buckets starting at
      // the same time would each resolve them.
      await api.resolvePath();

      final ok = await source.load();
      await _syncEntries();
      _isLoading = false;
      await _settle();

      return ok;
    });
  }

  /// Turns the page of *buckets*. A bucket still on the axis keeps its rows,
  /// its page and its scroll offset; only the ones that left are dropped.
  Future<bool> setGroupPage(int page) {
    _isLoading = true;
    _flushNotify();

    return _batched(() async {
      final ok = await source.setPage(page);
      await _syncEntries();
      _isLoading = false;
      await _settle();

      return ok;
    });
  }

  Future<bool> nextGroupPage() =>
      hasNextGroupPage ? setGroupPage(groupPage + 1) : Future.value(false);

  Future<bool> previousGroupPage() =>
      hasPreviousGroupPage ? setGroupPage(groupPage - 1) : Future.value(false);

  /// Changes part of the query of every bucket and re-reads them, each back to
  /// its first page. An argument left out keeps its current value.
  Future<bool> refine({
    Object? filter = _unset,
    Object? orderBy = _unset,
    Object? fields = _unset,
  }) async {
    if (!identical(filter, _unset)) {
      _filter = filter;
    }

    if (!identical(orderBy, _unset)) {
      _orderBy = orderBy;
      _sort = ListSort.empty;
    }

    if (!identical(fields, _unset)) {
      _fields = fields;
    }

    return _refineEntries();
  }

  /// Applies [sort] inside every bucket.
  Future<bool> sortBy(ListSort sort) async {
    _sort = sort;
    _orderBy = sort.isEmpty ? null : sort.toOrderBy();

    return _refineEntries();
  }

  Future<bool> cycleSort(String field, {bool additive = false}) =>
      sortBy(_sort.cycle(field, additive: additive));

  Future<bool> _refineEntries() => _batched(() async {
    await Future.wait([
      for (final entry in _entries)
        entry.collection.refine(
          filter: _filterFor(entry.group),
          orderBy: _orderBy,
          fields: _fields,
        ),
    ]);
    await _settle();

    return true;
  });

  /// Rebuilds the entry list from the axis, reusing by [ListGroup.key].
  Future<void> _syncEntries() async {
    if (_disposed) {
      return;
    }

    final previous = {for (final entry in _entries) entry.group.key: entry};
    final next = <GroupedEntry<T>>[];
    final fresh = <GroupedEntry<T>>[];

    for (final group in source.groups) {
      final kept = previous.remove(group.key);

      if (kept != null) {
        next.add(GroupedEntry(group, kept.collection));
        continue;
      }

      final entry = GroupedEntry(group, _newChild());
      next.add(entry);
      fresh.add(entry);
    }

    // The list is swapped before the dropped buckets are disposed: a
    // notification raised while disposing must never reach a listener that
    // could still read an entry being torn down.
    _entries = next;

    for (final dropped in previous.values) {
      dropped.collection.removeListener(_scheduleNotify);
      dropped.collection.dispose();
    }

    await Future.wait([
      for (final entry in fresh)
        entry.collection.refine(
          filter: _filterFor(entry.group),
          orderBy: _orderBy,
          fields: _fields,
        ),
    ]);
  }

  ApiCollection<T> _newChild() {
    final child = ApiCollection<T>(
      api,
      fields: _fields,
      orderBy: _orderBy,
      limit: rowLimit,
      // This collection holds the only subscription: N buckets each reloading
      // on every mutation is the cost this design exists to avoid.
      autoRefreshOnChange: false,
    );
    child.addListener(_scheduleNotify);

    return child;
  }

  Object? _filterFor(ListGroup group) => _filter == null
      ? group.predicate
      : [
          '&',
          [_filter, group.predicate],
        ];

  /// Aggregates the verdicts of the axis and the buckets into the one a screen
  /// renders on.
  ///
  /// A connection is required only when there is nothing showable at all: the
  /// axis could not be enumerated, or every bucket came back empty-handed. One
  /// bucket failing while its neighbours hold rows is that bucket's own band,
  /// not the whole screen — the rule [DataAvailabilityState.failRead] already
  /// states for a single collection.
  Future<void> _settle() async {
    if (_disposed) {
      return;
    }

    var fromCache = source.fromCache;
    var allOffline = _entries.isNotEmpty;
    Object? error = source.error;

    for (final entry in _entries) {
      final collection = entry.collection;
      fromCache = fromCache || collection.isFromCache;
      allOffline = allOffline && collection.requiresConnection;
      error ??= collection.error;
    }

    if (error != null && (source.requiresConnection || allOffline)) {
      failRead(error);
    } else {
      resolveRead(fromCache: fromCache);
    }

    await resolveModelFacts();
    _scheduleNotify();
  }

  Future<void> _onResourceChanged(ResourceChangedEvent event) async {
    if (!_loaded || _disposed) {
      return;
    }

    if (event.basePath == api.resolvedBasePath) {
      if (event.type == ResourceChangeType.deleted) {
        // Zero requests: the bucket holding the row drops it and adjusts its
        // own total.
        for (final entry in _entries) {
          if (entry.collection.removeLocal(event.id)) {
            break;
          }
        }

        await _settle();

        return;
      }

      _refresh?.cancel();
      _refresh = Timer(refreshDelay, _refreshEntries);

      return;
    }

    if (source.watchPath != null && event.basePath == source.watchPath) {
      _axisRefresh?.cancel();
      _axisRefresh = Timer(refreshDelay, _reloadAxis);
    }
  }

  /// Re-reads every visible bucket, once, after a burst of writes settled.
  ///
  /// All of them, not the ones holding the changed id: the bucket a record
  /// *moved to* cannot be known from here, and that is precisely the case of a
  /// record whose grouped field just changed.
  Future<void> _refreshEntries() async {
    if (_disposed) {
      return;
    }

    await _batched(() async {
      await Future.wait([
        for (final entry in _entries) entry.collection.refreshQuietly(),
      ]);
      await _settle();
    });
  }

  Future<void> _reloadAxis() async {
    if (_disposed) {
      return;
    }

    await _batched(() async {
      await source.load();
      await _syncEntries();
      await _settle();
    });
  }

  @override
  Future<void> healAvailability() async {
    if (!_loaded || _disposed || _isLoading) {
      return;
    }

    if (source.requiresConnection) {
      await _reloadAxis();

      return;
    }

    await _refreshEntries();
  }

  /// Runs a fan-out as one notification.
  ///
  /// Microtask coalescing alone cannot do it: the buckets are read across real
  /// await points, so their notifications land in different turns and a screen
  /// would rebuild once per bucket per state change. Inside a batch they are
  /// held, and one rebuild is raised when the whole operation settles.
  Future<R> _batched<R>(Future<R> Function() body) async {
    _batch++;

    try {
      return await body();
    } finally {
      _batch--;

      if (_batch == 0 && _batchNotify) {
        _batchNotify = false;
        _flushNotify();
      }
    }
  }

  void _scheduleNotify() {
    if (_disposed) {
      return;
    }

    if (_batch > 0) {
      _batchNotify = true;

      return;
    }

    if (_notifyScheduled) {
      return;
    }

    _notifyScheduled = true;
    scheduleMicrotask(_flushNotify);
  }

  void _flushNotify() {
    _notifyScheduled = false;

    if (_disposed) {
      return;
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refresh?.cancel();
    _axisRefresh?.cancel();
    _sub.cancel();
    disposeAvailability();

    for (final entry in _entries) {
      entry.collection.removeListener(_scheduleNotify);
      entry.collection.dispose();
    }

    source.dispose();
    super.dispose();
  }
}
