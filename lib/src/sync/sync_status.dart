/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../bus/bus.dart';
import '../bus/events.dart';
import '../container/container.dart';

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

  /// Whether the server is actually answering — [online] alone is not it, see
  /// [SyncStatus.reachable].
  final bool reachable;

  const SyncStatusChangedEvent({
    required this.online,
    required this.syncing,
    required this.pending,
    required this.conflicts,
    this.reachable = true,
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
  bool _serverAnswering = true;
  int _pending = 0;
  int _conflicts = 0;

  SyncStatus(this._bus, {this._online = true});

  /// Whether the server can be expected to answer, readable without holding the
  /// service — the question a UI gating an action actually has.
  ///
  /// True when there is no [SyncStatus] at all: a build without the offline
  /// write path never reports itself offline, so a caller gating on this one
  /// needs no `hasService` guard of its own.
  static bool get currentlyReachable =>
      hasService<SyncStatus>() ? getService<SyncStatus>().reachable : true;

  /// Whether the device currently has connectivity.
  ///
  /// Connectivity only: the device can be on a network whose server is down,
  /// which is why [reachable] exists.
  bool get online => _online;

  /// Whether the last request that reached the transport came back.
  ///
  /// Driven by the requests themselves, not by the connectivity stream: a
  /// stopped server, a maintenance window and a dead upstream all leave the
  /// device online.
  bool get serverAnswering => _serverAnswering;

  /// Whether the server can be expected to answer: connectivity **and**
  /// evidence from the last request.
  ///
  /// This is what an action gates on. [online] alone says a phone has wifi,
  /// which is not the same claim.
  bool get reachable => _online && _serverAnswering;

  /// Whether a flush of the outbox is in progress.
  bool get syncing => _syncing;

  /// Number of buffered writes still waiting to be replayed.
  int get pending => _pending;

  /// Number of conflicts parked for manual resolution.
  int get conflicts => _conflicts;

  /// Whether there is anything worth surfacing (unreachable, syncing, a
  /// non-empty queue, or a conflict) — convenience for hiding an idle indicator.
  bool get isActive => !reachable || _syncing || _pending > 0 || _conflicts > 0;

  void setOnline(bool value) {
    if (_online != value) {
      _online = value;

      // Connectivity coming back says nothing about the server yet; let the
      // next request answer that, rather than claiming reachable and having a
      // control flicker enabled.
      if (value) {
        _serverAnswering = true;
      }

      _emit();
    }
  }

  /// Records what a request just proved: an answer — any answer, a refusal
  /// included — means the server is there, and an unanswered one means it is not.
  ///
  /// Driven by the fetcher for every request, so no caller has to report it.
  void setServerAnswering(bool value) {
    if (_serverAnswering != value) {
      _serverAnswering = value;
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
        reachable: reachable,
      ),
    );
    notifyListeners();
  }
}
