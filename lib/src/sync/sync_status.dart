/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../bus/bus.dart';
import '../bus/events.dart';

/// Fired on every transition of the offline [SyncStatus] (connectivity change,
/// a flush starting or finishing, the pending queue growing or draining).
///
/// Carries the full snapshot so a listener never has to read the service back:
/// ```dart
/// bus.on<SyncStatusChangedEvent>().listen((e) {
///   if (!e.online) showOfflineBanner();
/// });
/// ```
class SyncStatusChangedEvent extends Event {
  final bool online;
  final bool syncing;
  final int pending;
  final int conflicts;

  const SyncStatusChangedEvent({
    required this.online,
    required this.syncing,
    required this.pending,
    required this.conflicts,
  });
}

/// Live, re-exposed state of the offline write path.
///
/// A single source of truth a UI can bind to for a connectivity/sync
/// indicator: whether the device is [online], whether a flush is currently
/// [syncing], and how many writes are still [pending] replay. Registered as a
/// container singleton when the offline outbox is enabled — resolve it with
/// `getService<SyncStatus>()` (guard with `hasService<SyncStatus>()` when
/// offline mode may be off).
///
/// It is both a [ChangeNotifier] (bind with `ListenableBuilder`) and a Bus
/// emitter ([SyncStatusChangedEvent]) — the fields are driven by the
/// [Outbox] (pending) and the [SyncEngine] (online/syncing).
class SyncStatus extends ChangeNotifier {
  final Bus _bus;

  bool _online;
  bool _syncing = false;
  int _pending = 0;
  int _conflicts = 0;

  SyncStatus(this._bus, {bool online = true}) : _online = online;

  /// Whether the device currently has connectivity.
  bool get online => _online;

  /// Whether a flush of the outbox is in progress.
  bool get syncing => _syncing;

  /// Number of buffered writes still waiting to be replayed.
  int get pending => _pending;

  /// Number of conflicts parked for manual resolution.
  int get conflicts => _conflicts;

  /// Whether there is anything worth surfacing (offline, syncing, a non-empty
  /// queue, or a conflict) — convenience for hiding an idle indicator.
  bool get isActive => !_online || _syncing || _pending > 0 || _conflicts > 0;

  void setOnline(bool value) {
    if (_online != value) {
      _online = value;
      _emit();
    }
  }

  void setSyncing(bool value) {
    if (_syncing != value) {
      _syncing = value;
      _emit();
    }
  }

  void setPending(int value) {
    if (_pending != value) {
      _pending = value;
      _emit();
    }
  }

  void setConflicts(int value) {
    if (_conflicts != value) {
      _conflicts = value;
      _emit();
    }
  }

  void _emit() {
    _bus.fire(
      SyncStatusChangedEvent(
        online: _online,
        syncing: _syncing,
        pending: _pending,
        conflicts: _conflicts,
      ),
    );
    notifyListeners();
  }
}
