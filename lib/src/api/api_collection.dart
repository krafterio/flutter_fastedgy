import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';

class ApiCollection<T extends BaseModel<T>> extends ChangeNotifier {
  ApiCollection(this.api);

  final ApiModel<T> api;

  List<T> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
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
    final size = query?.size ?? query?.limit;
    if (size != null) _limit = size;
    return _fetch(1, append: false);
  }

  Future<bool> reload() => _fetch(_page, append: false);

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
      fields: base?.fields,
      filter: _effectiveFilter(),
      orderBy: base?.orderBy,
      limit: _limit,
      offset: _limit != null ? (page - 1) * _limit! : null,
    );
  }

  FieldsOptions? _defaultFields() {
    final fields = _query?.fields;
    return fields == null ? null : FieldsOptions(fields: fields);
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

  Future<T?> create(T draft, {FieldsOptions? options}) async {
    try {
      final created = await api.create(draft, options: options ?? _defaultFields());
      _items = [..._items, created];
      _total += 1;
      _error = null;
      _safeNotify();
      return created;
    } catch (e) {
      _error = e;
      _safeNotify();
      return null;
    }
  }

  Future<T?> update(Object id, T patch, {FieldsOptions? options}) async {
    try {
      final updated = await api.update(id, patch, options: options ?? _defaultFields());
      _items = [for (final e in _items) e.id == updated.id ? updated : e];
      _error = null;
      _safeNotify();
      return updated;
    } catch (e) {
      _error = e;
      _safeNotify();
      return null;
    }
  }

  Future<bool> delete(Object id) async {
    try {
      await api.delete(id);
      _items = _items.where((e) => e.id != id).toList();
      if (_total > 0) _total -= 1;
      _error = null;
      _safeNotify();
      return true;
    } catch (e) {
      _error = e;
      _safeNotify();
      return false;
    }
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
    super.dispose();
  }
}
