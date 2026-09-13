/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import '../api/api_model.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import 'realtime_events.dart';
import 'realtime_socket.dart';

/// Hears the changes of what [api] holds, of one record of it when [id] is
/// set, and keeps its channel subscribed on the realtime socket while it lives.
///
/// [where] judges what reached it, [refreshDelay] collapses a burst into its
/// last event. Anything asking every holder to read again, a socket coming
/// back for one, calls [onChanged] at once with an event naming no type and no
/// id.
ResourceWatch watchResource(
  ApiModel<dynamic> api,
  void Function(ResourceChangedEvent event) onChanged, {
  Object? id,
  bool Function(ResourceChangedEvent event)? where,
  Duration refreshDelay = const Duration(milliseconds: 250),
}) => ResourceWatch._(api, onChanged, id, where, refreshDelay);

class ResourceWatch {
  ResourceWatch._(
    this._api,
    this._onChanged,
    this._id,
    this._where,
    this._refreshDelay,
  ) : _socket = hasService<RealtimeSocket>()
          ? getService<RealtimeSocket>()
          : null {
    final bus = getService<Bus>();

    _changes = bus.on<ResourceChangedEvent>().listen(_heard);
    _stale = bus.on<ResourcesStaleEvent>().listen((_) => _heardStale());
    _subscribe();
  }

  final ApiModel<dynamic> _api;
  final void Function(ResourceChangedEvent event) _onChanged;
  final bool Function(ResourceChangedEvent event)? _where;
  final Duration _refreshDelay;
  final RealtimeSocket? _socket;

  late final StreamSubscription<ResourceChangedEvent> _changes;
  late final StreamSubscription<ResourcesStaleEvent> _stale;
  Object? _id;
  Timer? _pending;
  bool _active = true;
  bool _owed = false;
  bool _cancelled = false;

  Object? get id => _id;

  /// Moves the watch to another record, its channel with it; a call pending
  /// for the record left is dropped.
  set id(Object? value) {
    if (value == _id || (value != null && '$value' == '$_id')) {
      return;
    }

    if (_cancelled) {
      _id = value;

      return;
    }

    _unsubscribe();
    _pending?.cancel();
    _pending = null;
    _id = value;
    _subscribe();
  }

  /// Whether what holds this watch can be seen. Off screen, nothing is
  /// delivered: what came is owed as one call once it is shown again.
  bool get active => _active;

  set active(bool value) {
    if (value == _active) {
      return;
    }

    _active = value;

    if (value && _owed) {
      _owed = false;
      _deliver(_staleEvent);
    }
  }

  /// Stops hearing, and lets go of the channel once however often it is called.
  void cancel() {
    if (_cancelled) {
      return;
    }

    _cancelled = true;
    _pending?.cancel();
    unawaited(_changes.cancel());
    unawaited(_stale.cancel());
    _unsubscribe();
  }

  ResourceChangedEvent get _staleEvent =>
      ResourceChangedEvent(_api.resolvedBasePath, model: _api.modelName);

  void _heard(ResourceChangedEvent event) {
    if (_cancelled || !event.isAbout(_api)) {
      return;
    }

    final id = _id;

    if (id != null && event.id != null && '${event.id}' != '$id') {
      return;
    }

    if (_where?.call(event) == false) {
      return;
    }

    _pending?.cancel();

    if (_refreshDelay == Duration.zero) {
      _deliver(event);

      return;
    }

    _pending = Timer(_refreshDelay, () {
      _pending = null;
      _deliver(event);
    });
  }

  void _heardStale() {
    if (_cancelled) {
      return;
    }

    _pending?.cancel();
    _pending = null;
    _deliver(_staleEvent);
  }

  void _deliver(ResourceChangedEvent event) {
    if (_cancelled) {
      return;
    }

    if (!_active) {
      _owed = true;

      return;
    }

    _onChanged(event);
  }

  void _subscribe() {
    final model = _api.modelName;

    if (model != null) {
      _socket?.subscribe(model, _id);
    }
  }

  void _unsubscribe() {
    final model = _api.modelName;

    if (model != null) {
      _socket?.unsubscribe(model, _id);
    }
  }
}
