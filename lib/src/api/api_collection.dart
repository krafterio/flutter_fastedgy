import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';
import 'data_availability.dart';
import 'list_sort.dart';

class ApiCollection<T extends BaseModel<T>> extends ChangeNotifier
    with DataAvailabilityState<T> {
  ApiCollection(
    this.api, {
    dynamic fields,
    dynamic orderBy,
    int? limit,
    bool autoRefreshOnChange = true,
  }) : _configFields = fields,
       _configOrderBy = orderBy,
       _limit = limit {
    if (autoRefreshOnChange) {
      _sub = getService<Bus>().on<ResourceChangedEvent>().listen(
        _onResourceChanged,
      );
    }

    listenAvailability();
  }

  /// Tells "not provided" from "set to null" in [refine].
  static const Object _unset = Object();

  @override
  final ApiModel<T> api;
  final dynamic _configFields;
  final dynamic _configOrderBy;

  StreamSubscription<ResourceChangedEvent>? _sub;

  List<T> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _loaded = false;
  Object? _error;
  bool _disposed = false;

  /// Whether the collection already holds loaded data. A screen can read this
  /// before [load] to decide whether to play its entry animation (skip it when
  /// the collection — kept alive by a durable holder — is already populated).
  bool get isLoaded => _loaded;

  /// Last known scroll offset of the list bound to this collection. The screen
  /// wires its [ScrollController] to it (initialScrollOffset + a listener that
  /// writes back). It survives navigation with the collection instance, so the
  /// scroll position is restored without any global cache.
  double scrollOffset = 0;

  ListQuery? _query;
  int? _limit;
  int _page = 1;
  int _total = 0;
  int _totalPages = 0;
  ListSort _sort = ListSort.empty;

  /// Bumped by every read that replaces the list. A response carrying an older
  /// generation lost the race — typing in a search field fires one request per
  /// keystroke, and the last one to *answer* is not the last one asked.
  int _generation = 0;

  @override
  bool get hasData => _items.isNotEmpty;

  @override
  void notifyAvailability() => _safeNotify();

  /// True when the read settled and brought nothing back: an empty state is
  /// honest here, unlike [requiresConnection]. Pair it with [isIncomplete] to
  /// soften the wording when the mirror only holds part of the model.
  bool get isEmpty =>
      !hasData &&
      (availability == DataAvailability.live ||
          availability == DataAvailability.cached);

  List<T> get items => _items;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  Object? get error => _error;
  int get page => _page;
  int get total => _total;
  int get totalPages => _totalPages;
  int? get limit => _limit;
  bool get hasNextPage => _page < _totalPages;
  bool get hasPreviousPage => _page > 1;
  bool get hasMore => hasNextPage;

  /// Ordering the header is driving, empty when the server's own default
  /// applies. Only [sortBy] and [cycleSort] set it: an `orderBy` passed to
  /// [refine] or [load] bypasses the header and clears it.
  ListSort get sort => _sort;

  /// Effective request parts, each falling back to what the constructor
  /// declared. Read by every fetch path so a refine on one of them cannot drop
  /// the others.
  dynamic get fields => _query?.fields ?? _configFields;
  dynamic get orderBy => _query?.orderBy ?? _configOrderBy;
  dynamic get filter => _query?.filter;

  T? byId(Object? id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<bool> load({ListQuery? query}) {
    _query = query;
    _sort = ListSort.empty;
    _loaded = true;
    final size = query?.size ?? query?.limit;
    if (size != null) _limit = size;
    return _fetch(1, append: false);
  }

  /// Loads pages 1..[page] in a single request (offset 0, limit = pageSize ×
  /// page) so a screen can restore its previous pagination depth — and thus its
  /// scroll position — at once. Falls back to a normal first-page load when the
  /// page size is unknown or [page] <= 1.
  ///
  /// A [query] replaces the current one; without it the collection keeps the
  /// parts it already had.
  Future<bool> loadThroughPage(int page, {ListQuery? query}) {
    if (query != null) {
      _query = query;
      _sort = ListSort.empty;
      final size = query.size ?? query.limit;
      if (size != null) _limit = size;
    }

    _loaded = true;

    return _fetch(page, append: false, through: true);
  }

  /// Changes part of the query and re-reads from [page] (first page by
  /// default), in a single request: an argument left out keeps its current
  /// value, passing null clears it.
  ///
  /// What is on screen — items, total, availability — stays until the response
  /// lands, so a filter typed letter by letter does not blink through an empty
  /// list.
  Future<bool> refine({
    Object? filter = _unset,
    Object? orderBy = _unset,
    Object? fields = _unset,
    Object? limit = _unset,
    ListSort? sort,
    int? page,
  }) {
    if (sort != null) {
      // Both in one request: restoring a filter and an ordering from a URL must
      // not cost two reads, and the intermediate one would show the wrong order.
      _sort = sort;
      orderBy = sort.isEmpty ? null : sort.toOrderBy();
    } else if (!identical(orderBy, _unset)) {
      _sort = ListSort.empty;
    }

    return _refine(
      filter: filter,
      orderBy: orderBy,
      fields: fields,
      limit: limit,
      page: page,
    );
  }

  /// Applies [sort] as the ordering and returns to the first page — a new
  /// ordering makes the current page number meaningless. An empty sort sends no
  /// `order_by` at all, which is how the server is asked for its own default.
  Future<bool> sortBy(ListSort sort) {
    _sort = sort;

    return _refine(orderBy: sort.isEmpty ? null : sort.toOrderBy());
  }

  /// Advances [field]'s ordering phase, as a click on its column header does
  /// (see [ListSort.cycle]).
  Future<bool> cycleSort(String field, {bool additive = false}) =>
      sortBy(_sort.cycle(field, additive: additive));

  Future<bool> _refine({
    Object? filter = _unset,
    Object? orderBy = _unset,
    Object? fields = _unset,
    Object? limit = _unset,
    int? page,
  }) {
    _query = ListQuery(
      fields: identical(fields, _unset) ? _query?.fields : fields,
      orderBy: identical(orderBy, _unset) ? _query?.orderBy : orderBy,
      filter: identical(filter, _unset) ? _query?.filter : filter,
    );

    if (!identical(limit, _unset)) {
      _limit = limit as int?;
    }

    _loaded = true;

    return _fetch(page ?? 1, append: false, through: (page ?? 1) > 1);
  }

  Future<bool> reload() => _fetch(1, append: false);

  /// Applies a new item order in place (optimistic reorder) — no fetch, no
  /// loading state. Pair it with a server resequence; the follow-up refresh
  /// returns the same order, so the list does not flicker or jump back.
  void reorder(List<T> ordered) {
    _items = ordered;
    _safeNotify();
  }

  /// Drops the row [id] and adjusts the totals, without a request — what a
  /// `deleted` event costs when the collection is told about it rather than
  /// re-reading its page. Returns whether the collection held that row.
  bool removeLocal(Object? id) {
    final before = _items.length;
    _items = _items.where((e) => e.id != id).toList();

    if (_items.length == before) {
      return false;
    }

    if (_total > 0) _total -= 1;

    if (_limit != null && _limit! > 0) {
      _totalPages = (_total / _limit!).ceil();
    }

    _safeNotify();

    return true;
  }

  /// Re-reads the loaded range without a loading state, keeping the current
  /// rows if it fails. The refresh path of a holder driven from outside (a
  /// mutation elsewhere, connectivity coming back).
  Future<void> refreshQuietly() => _refreshLoadedRange();

  Future<void> _onResourceChanged(ResourceChangedEvent event) async {
    if (!_loaded || _disposed || event.basePath != api.resolvedBasePath) return;
    if (event.type == ResourceChangeType.deleted) {
      removeLocal(event.id);
      return;
    }
    await _refreshLoadedRange();
  }

  Future<void> _refreshLoadedRange() async {
    if (_disposed) return;
    final pageSize = _limit;
    final generation = _generation;
    try {
      final result = await api.list(
        query: ListQuery(
          fields: fields,
          orderBy: orderBy,
          filter: filter,
          limit: pageSize != null ? pageSize * _page : null,
          offset: 0,
        ),
      );
      if (_disposed || generation != _generation) return;
      _items = result.items;
      _total = result.total;
      _totalPages = pageSize != null && pageSize > 0
          ? (result.total / pageSize).ceil()
          : result.totalPages;
      _error = null;
      resolveRead(fromCache: result.fromCache);
      await resolveModelFacts();
      _safeNotify();
    } catch (_) {
      // A silent refresh that fails leaves the availability alone: what is on
      // screen did not change, and claiming a missing connection while showing
      // rows would contradict requiresConnection.
    }
  }

  /// Silently re-reads the loaded range — the recovery path when connectivity
  /// comes back on a collection that fell back to the mirror or found nothing
  /// to fall back on.
  @override
  Future<void> healAvailability() async {
    if (!_loaded || _disposed || _isLoading || _isLoadingMore) return;
    await _refreshLoadedRange();
  }

  Future<bool> setPage(int page) => _fetch(page, append: false);

  Future<bool> nextPage() =>
      hasNextPage ? _fetch(_page + 1, append: false) : Future.value(false);

  Future<bool> previousPage() =>
      hasPreviousPage ? _fetch(_page - 1, append: false) : Future.value(false);

  Future<bool> loadMore() {
    if (_isLoadingMore || _isLoading || !hasNextPage) {
      return Future.value(false);
    }
    return _fetch(_page + 1, append: true);
  }

  Future<bool> setLimit(int? limit) {
    _limit = limit;
    return _fetch(1, append: false);
  }

  /// Reads one page. [through] asks for pages 1..page at once (see
  /// [loadThroughPage]) and is ignored when the page size is unknown.
  Future<bool> _fetch(
    int page, {
    required bool append,
    bool through = false,
  }) async {
    final pageSize = _limit;
    final spansPages = through && page > 1 && pageSize != null && pageSize > 0;
    // Without a known page size there is no offset to compute, so a
    // through-page read can only be the first page.
    final target = spansPages || !through ? page : 1;

    if (append) {
      _isLoadingMore = true;
    } else {
      _isLoading = true;
    }

    final generation = append ? _generation : ++_generation;
    _error = null;
    beginRead();
    _safeNotify();
    try {
      final result = await api.list(
        query: spansPages
            ? _throughQuery(target, pageSize)
            : _pageQuery(target),
      );
      if (_disposed || generation != _generation) return false;
      _page = target;
      _total = result.total;
      if (spansPages) {
        _totalPages = (result.total / pageSize).ceil();
      } else {
        _totalPages = result.totalPages;
        if (result.limit > 0) _limit = result.limit;
      }
      if (append) {
        final existingIds = {for (final e in _items) e.id};
        _items = [
          ..._items,
          ...result.items.where((e) => !existingIds.contains(e.id)),
        ];
      } else {
        _items = result.items;
      }
      resolveRead(fromCache: result.fromCache);
      return true;
    } catch (e) {
      if (_disposed || generation != _generation) return false;
      _error = e;
      failRead(e);
      return false;
    } finally {
      // A response that lost the race leaves every bit of state to the read
      // that superseded it, the loading flag included: that one is still in
      // flight and owns it.
      if (!_disposed && generation == _generation) {
        await resolveModelFacts();
        if (append) {
          _isLoadingMore = false;
        } else {
          _isLoading = false;
        }
        _safeNotify();
      }
    }
  }

  ListQuery _pageQuery(int page) => ListQuery(
    fields: fields,
    orderBy: orderBy,
    filter: filter,
    limit: _limit,
    offset: _limit != null ? (page - 1) * _limit! : null,
  );

  ListQuery _throughQuery(int page, int pageSize) => ListQuery(
    fields: fields,
    orderBy: orderBy,
    filter: filter,
    limit: pageSize * page,
    offset: 0,
  );

  void _safeNotify() {
    if (_disposed) return;
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
    _sub?.cancel();
    disposeAvailability();
    super.dispose();
  }
}
