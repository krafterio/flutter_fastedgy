import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';

/// Reactive holder for a SINGLE record — the single-record counterpart of
/// [ApiCollection].
///
/// It subscribes to [ResourceChangedEvent] and, for the loaded record:
/// - silently re-fetches it on an external **update** (no loader) so the screen
///   reflects the new values;
/// - flips [isDeleted] on an external **delete** (and clears [value]) so the
///   screen can close itself.
///
/// "External" covers any mutation made outside this screen — another client, or
/// the AI agent. A detail/edit screen creates one in `initState`, [load]s its id,
/// listens to it (re-sync its UI on change, close when [isDeleted]) and
/// [dispose]s it. Same wiring as [ApiCollection], minus the pagination.
class ApiRecord<T extends BaseModel<T>> extends ChangeNotifier {
  ApiRecord(this.api, {dynamic fields}) : _configFields = fields {
    _sub = getService<Bus>().on<ResourceChangedEvent>().listen(
      _onResourceChanged,
    );
  }

  final ApiModel<T> api;
  dynamic _configFields;

  late final StreamSubscription<ResourceChangedEvent> _sub;

  Object? _id;
  T? _value;
  bool _isLoading = false;
  bool _loaded = false;
  bool _deleted = false;
  Object? _error;
  bool _disposed = false;

  /// The loaded record (null before [load], or after an external delete).
  T? get value => _value;

  /// The id currently bound, set by [load].
  Object? get id => _id;

  bool get isLoading => _isLoading;

  /// Whether [load] has run at least once (the holder holds — or held — a record).
  bool get isLoaded => _loaded;

  /// True once the bound record was deleted elsewhere — the screen should close.
  bool get isDeleted => _deleted;

  Object? get error => _error;

  FieldsOptions? get _options =>
      _configFields != null ? FieldsOptions(fields: _configFields) : null;

  /// Fetch [id] (loader shown). [fields] overrides the constructor field selection.
  /// Keeps the previous [value] until the new one arrives (no null flash on reload).
  Future<bool> load(Object id, {dynamic fields}) async {
    _id = id;
    _loaded = true;
    _deleted = false;
    if (fields != null) _configFields = fields;
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      _value = await api.get(id, options: _options);
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<bool> reload() => _id != null ? load(_id!) : Future.value(false);

  Future<void> _onResourceChanged(ResourceChangedEvent event) async {
    if (!_loaded || _disposed || _id == null) return;
    if (event.basePath != api.resolvedBasePath || event.id != _id) return;
    if (event.type == ResourceChangeType.deleted) {
      _deleted = true;
      _value = null;
      _safeNotify();
      return;
    }
    await _refresh();
  }

  // Silent re-fetch (no loader) — the bound record was mutated elsewhere.
  Future<void> _refresh() async {
    if (_disposed || _id == null) return;
    try {
      final value = await api.get(_id!, options: _options);
      if (_disposed) return;
      _value = value;
      _safeNotify();
    } catch (_) {}
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
