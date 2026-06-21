import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';

class ApiCollection<T extends BaseModel<T>> extends ChangeNotifier {
  ApiCollection(this.api, {dynamic fields, dynamic orderBy, int? limit})
    : _configFields = fields,
      _configOrderBy = orderBy,
      _limit = limit {
    _sub = getService<Bus>().on<ResourceChangedEvent>().listen(
      _onResourceChanged,
    );
  }

  final ApiModel<T> api;
  final dynamic _configFields;
  final dynamic _configOrderBy;

  late final StreamSubscription<ResourceChangedEvent> _sub;

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

  T? byId(Object? id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<bool> load({ListQuery? query}) {
    _query = query;
    _loaded = true;
    final size = query?.size ?? query?.limit;
    if (size != null) _limit = size;
    return _fetch(1, append: false);
  }

  /// Loads pages 1..[page] in a single request (offset 0, limit = pageSize ×
  /// page) so a screen can restore its previous pagination depth — and thus its
  /// scroll position — at once. Falls back to a normal first-page load when the
  /// page size is unknown or [page] <= 1.
  Future<bool> loadThroughPage(int page, {ListQuery? query}) async {
    _query = query;
    _loaded = true;
    final size = query?.size ?? query?.limit;
    if (size != null) _limit = size;
    final pageSize = _limit;
    if (pageSize == null || pageSize <= 0 || page <= 1) {
      return _fetch(1, append: false);
    }
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      final result = await api.list(
        query: ListQuery(
          fields: query?.fields ?? _configFields,
          orderBy: query?.orderBy ?? _configOrderBy,
          filter: _query?.filter,
          limit: pageSize * page,
          offset: 0,
        ),
      );
      if (_disposed) return false;
      _page = page;
      _total = result.total;
      _totalPages = (result.total / pageSize).ceil();
      _items = result.items;
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<bool> reload() => _fetch(1, append: false);

  Future<void> _onResourceChanged(ResourceChangedEvent event) async {
    if (!_loaded || _disposed || event.basePath != api.basePath) return;
    if (event.type == ResourceChangeType.deleted) {
      final before = _items.length;
      _items = _items.where((e) => e.id != event.id).toList();
      if (_items.length != before) {
        if (_total > 0) _total -= 1;
        if (_limit != null && _limit! > 0) {
          _totalPages = (_total / _limit!).ceil();
        }
        _safeNotify();
      }
      return;
    }
    await _refreshLoadedRange();
  }

  Future<void> _refreshLoadedRange() async {
    if (_disposed) return;
    final pageSize = _limit;
    try {
      final result = await api.list(
        query: ListQuery(
          fields: _query?.fields ?? _configFields,
          orderBy: _query?.orderBy ?? _configOrderBy,
          filter: _query?.filter,
          limit: pageSize != null ? pageSize * _page : null,
          offset: 0,
        ),
      );
      if (_disposed) return;
      _items = result.items;
      _total = result.total;
      _totalPages = pageSize != null && pageSize > 0
          ? (result.total / pageSize).ceil()
          : result.totalPages;
      _safeNotify();
    } catch (_) {}
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

  Future<bool> _fetch(int page, {required bool append}) async {
    if (append) {
      _isLoadingMore = true;
    } else {
      _isLoading = true;
    }
    _error = null;
    _safeNotify();
    try {
      final result = await api.list(query: _pageQuery(page));
      _page = page;
      _total = result.total;
      _totalPages = result.totalPages;
      if (result.limit > 0) _limit = result.limit;
      if (append) {
        final existingIds = {for (final e in _items) e.id};
        _items = [
          ..._items,
          ...result.items.where((e) => !existingIds.contains(e.id)),
        ];
      } else {
        _items = result.items;
      }
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      if (append) {
        _isLoadingMore = false;
      } else {
        _isLoading = false;
      }
      _safeNotify();
    }
  }

  ListQuery _pageQuery(int page) {
    final base = _query;
    return ListQuery(
      fields: base?.fields ?? _configFields,
      orderBy: base?.orderBy ?? _configOrderBy,
      filter: base?.filter,
      limit: _limit,
      offset: _limit != null ? (page - 1) * _limit! : null,
    );
  }

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
    _sub.cancel();
    super.dispose();
  }
}
