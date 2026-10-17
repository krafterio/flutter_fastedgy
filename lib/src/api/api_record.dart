import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../fetcher/http_error.dart';
import '../realtime/resource_watch.dart';
import 'api_holders.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';
import 'data_availability.dart';
import 'local_writes.dart';

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
///
/// Its writes, [update] and [delete], show before the server answers, on every
/// holder of the record ([LocalWrites]); the echo of its own write is not read.
class ApiRecord<T extends BaseModel<T>> extends ChangeNotifier
    with DataAvailabilityState<T>, LocalWrites<T>
    implements ApiHolder, ActiveHolder {
  ApiRecord(this.api, {dynamic fields}) : _configFields = fields {
    listenAvailability();
    followPatches();
  }

  @override
  final ApiModel<T> api;
  dynamic _configFields;

  ResourceWatch? _watch;
  bool _active = true;

  /// Whether its screen can be seen: off screen, what changes is owed as one
  /// read when it is shown again.
  @override
  bool get active => _active;

  @override
  set active(bool value) {
    _active = value;
    _watch?.active = value;
  }

  Object? _id;
  T? _value;
  int _writing = 0;
  bool _isLoading = false;
  bool _loaded = false;
  bool _deleted = false;
  Object? _error;
  bool _disposed = false;

  /// The loaded record (null before [load], or after an external delete).
  T? get value => _value;

  @override
  bool get hasData => _value != null;

  @override
  void notifyAvailability() => _safeNotify();

  /// The id currently bound, set by [load].
  Object? get id => _id;

  @override
  bool get isLoading => _isLoading;

  /// Whether [load] has run at least once (the holder holds — or held — a record).
  @override
  bool get isLoaded => _loaded;

  /// True once the bound record was deleted elsewhere — the screen should close.
  bool get isDeleted => _deleted;

  @override
  Object? get error => _error;

  FieldsOptions? get _options =>
      _configFields != null ? FieldsOptions(fields: _configFields) : null;

  @override
  dynamic get writeFields => _configFields;

  @override
  T? byId(Object? id) => id != null && '$id' == '$_id' ? _value : null;

  /// Puts [item] in place of the record when it is the one bound.
  @override
  bool upsertLocal(T item, {bool prepend = false}) {
    if (byId(item.id) != null) {
      _value = item;
      _safeNotify();
    }

    return false;
  }

  /// The record stays until the server says it is gone: its screen leaves on
  /// [isDeleted].
  @override
  VoidCallback? takeLocal(Object? id) => null;

  @override
  Future<R> writing<R>(Future<R> Function() write) async {
    _writing += 1;

    try {
      return await write();
    } finally {
      // An api hands what a write announces to the bus on a timer, once the
      // write returned to its caller: the changes are read again after it.
      Timer.run(() => _writing -= 1);
    }
  }

  /// The record bound, or its id alone while its first read runs.
  T get _bound {
    final id = _id;

    if (id == null) {
      throw StateError('No record is bound');
    }

    return _value ?? api.fromJson({'id': id is int ? id : int.parse('$id')});
  }

  /// Shows [values] in the record at once, then writes them (see
  /// [LocalWrites.updateItem]); a refusal puts back what it held and is
  /// thrown.
  Future<T> update(Map<String, Object?> values) => updateItem(_bound, values);

  /// Shows [values] in the record at once while [write] sends them (see
  /// [LocalWrites.updateItemWith]): an action of the model, a route of its
  /// own. A refusal puts back what it held and is thrown.
  Future<R> updateWith<R>(
    Map<String, Object?> values,
    Future<R> Function(Map<String, Object?> sent) write,
  ) => updateItemWith(_bound, values, write);

  /// Deletes the record, taken out at once from every list holding it, then
  /// marks it [isDeleted]; a refusal puts it back in them and is thrown.
  Future<void> delete() async {
    await deleteItem(_bound);
    _markDeleted();
  }

  /// Fetch [id] (loader shown). [fields] overrides the constructor field selection.
  /// Keeps the previous [value] until the new one arrives (no null flash on reload).
  ///
  /// A [seed] is the record the caller already holds (the row a list opened):
  /// it is shown at once, without a loader, then read again silently unless
  /// [reread] is false.
  Future<bool> load(
    Object id, {
    dynamic fields,
    T? seed,
    bool reread = true,
  }) async {
    _id = id;

    final watch = _watch;

    if (watch == null) {
      _watch = watchResource(
        api,
        _onResourceChanged,
        id: id,
        refreshDelay: Duration.zero,
      )..active = _active;
    } else {
      watch.id = id;
    }

    _loaded = true;
    _deleted = false;
    if (fields != null) _configFields = fields;

    if (seed != null) {
      _value = seed;
      _isLoading = false;
      _error = null;
      resolveRead(fromCache: false);
      _safeNotify();

      if (reread) {
        await _refresh();
      } else {
        await resolveModelFacts();
      }

      return true;
    }

    _isLoading = true;
    _error = null;
    beginRead();
    _safeNotify();
    try {
      final result = await api.getResult(id, options: _options);
      _value = result.value;
      resolveRead(fromCache: result.fromCache);
      return true;
    } catch (e) {
      _error = e;
      failRead(e);
      return false;
    } finally {
      await resolveModelFacts();
      _isLoading = false;
      _safeNotify();
    }
  }

  @override
  Future<bool> reload() => _id != null ? load(_id!) : Future.value(false);

  Future<void> _onResourceChanged(ResourceChangedEvent event) async {
    if (!_loaded || _disposed || _id == null || _writing > 0) return;
    // An event naming no record may be about this one: a read tells.
    if (event.type == ResourceChangeType.deleted && event.id != null) {
      _markDeleted();
      return;
    }
    await _refresh();
  }

  void _markDeleted() {
    _deleted = true;
    _value = null;
    _safeNotify();
  }

  // Silent re-fetch (no loader) — the bound record was mutated elsewhere.
  Future<void> _refresh() async {
    if (_disposed || _id == null) return;
    try {
      final result = await api.getResult(_id!, options: _options);
      if (_disposed) return;
      _value = result.value;
      _error = null;
      resolveRead(fromCache: result.fromCache);
      await resolveModelFacts();
      _safeNotify();
    } on HttpError catch (error) {
      if (error.statusCode == 404 && !_disposed) {
        _markDeleted();
      }
    } catch (_) {
      // A silent refresh that fails leaves the availability alone: the record on
      // screen did not change.
    }
  }

  /// Silently re-reads the bound record — the recovery path when connectivity
  /// comes back on a record served by the mirror, or never served at all.
  @override
  Future<void> healAvailability() async {
    if (!_loaded || _disposed || _deleted || _isLoading) return;
    await _refresh();
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
    _watch?.cancel();
    stopFollowingPatches();
    disposeAvailability();
    super.dispose();
  }
}
