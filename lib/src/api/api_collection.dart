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
  Object? _error;
  bool _disposed = false;
  ListQuery? _lastQuery;

  List<T> get items => _items;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  T? byId(Object? id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<bool> load({ListQuery? query}) async {
    _lastQuery = query;
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      _items = (await api.list(query: query)).items;
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<bool> reload() => load(query: _lastQuery);

  Future<T?> create(T draft, {FieldsOptions? options}) async {
    try {
      final created = await api.create(draft, options: options);
      _items = [..._items, created];
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
      final updated = await api.update(id, patch, options: options);
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
