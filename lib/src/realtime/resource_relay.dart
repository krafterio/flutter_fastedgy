/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import '../api/api_model_engine.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import '../logging/logging.dart';

/// Carries [ResourceChangedEvent]s between separate app instances (e.g. detached
/// desktop windows, each its own process). Implementations pick the channel — a
/// Unix-socket / named-pipe hub, a file drop, whatever fits the platform — so
/// the relay itself stays transport-agnostic.
abstract class ResourceRelayTransport {
  /// Open the channel (bind/connect, elect a hub…). Must not throw.
  Future<void> start();

  /// Push one event to every OTHER instance. [event] is a serialized
  /// [ResourceChangedEvent] (see [ResourceChangedEvent.toJson]).
  void broadcast(Map<String, dynamic> event);

  /// Events emitted by other instances, in the same map shape as [broadcast].
  Stream<Map<String, dynamic>> get incoming;

  Future<void> dispose();
}

/// Bridges the local [Bus] to a [ResourceRelayTransport]: every local mutation
/// event goes out to the other instances, and every event coming back is
/// re-fired locally flagged `relayed` so their `ApiCollection`/`ApiRecord`
/// holders refresh — exactly as they already do for in-process mutations. Every
/// resource gets cross-instance live sync for free; nothing per-feature to add.
class ResourceEventRelay {
  ResourceEventRelay(this._transport, {Bus? bus})
    : _bus = bus ?? getService<Bus>();

  final ResourceRelayTransport _transport;
  final Bus _bus;
  final _log = getLogger('resource_relay');

  StreamSubscription<ResourceChangedEvent>? _outSub;
  StreamSubscription<Map<String, dynamic>>? _inSub;
  bool _disposed = false;

  Future<void> start() async {
    try {
      await _transport.start();
    } catch (e, s) {
      _log.warning('Resource relay transport failed to start', e, s);
      return;
    }

    // Local mutations (relayed == false) go out; relayed ones are skipped to
    // avoid an echo loop back onto the wire.
    _outSub = _bus.on<ResourceChangedEvent>().listen((event) {
      if (_disposed || event.relayed) {
        return;
      }
      _transport.broadcast(event.toJson());
    });

    // Remote mutations come back and are re-fired locally, flagged relayed.
    _inSub = _transport.incoming.listen((json) {
      if (_disposed) {
        return;
      }
      _bus.fire(ResourceChangedEvent.fromJson(json, relayed: true));
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _outSub?.cancel();
    await _inSub?.cancel();
    await _transport.dispose();
  }
}
