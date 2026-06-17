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
    _sub = getService<Bus>().on<ResourceChangedEvent>().listen((event) {
      if (_loaded && event.basePath == api.basePath) reload();
    });
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

  ListQuery? _query;
  String? _search;
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
  String? get searchTerm => _search;
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

  Future<bool> reload() => _fetch(1, append: false);

  Future<bool> setPage(int page) => _fetch(page, append: false);

  Future<bool> nextPage() => hasNextPage ? _fetch(_page + 1, append: false) : Future.value(false);

  Future<bool> previousPage() => hasPreviousPage ? _fetch(_page - 1, append: false) : Future.value(false);

  Future<bool> loadMore() {
    if (_isLoadingMore || _isLoading || !hasNextPage) return Future.value(false);
    return _fetch(_page + 1, append: true);
  }

  Future<bool> setLimit(int? limit) {
    _limit = limit;
    return _fetch(1, append: false);
  }

  Future<bool> search(String? term) {
    final value = (term != null && term.trim().isNotEmpty) ? term.trim() : null;
    if (value == _search) return Future.value(true);
    _search = value;
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
        _items = [..._items, ...result.items.where((e) => !existingIds.contains(e.id))];
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
      filter: _effectiveFilter(),
      limit: _limit,
      offset: _limit != null ? (page - 1) * _limit! : null,
    );
  }

  dynamic _effectiveFilter() {
    final base = _query?.filter;
    if (_search == null) return base;
    final searchExpr = ['search_value', 'search_fuzzy', _search];
    if (base == null) return searchExpr;
    return [
      '&',
      [base, searchExpr],
    ];
  }

  void _safeNotify() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
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
