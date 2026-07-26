/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import '../bus/bus.dart';
import '../container/container.dart';
import '../fetcher/http_error.dart';
import '../sync/sync_status.dart';
import 'api_model.dart';
import 'base_model.dart';
import 'model_availability.dart';

/// Where the data a holder shows came from, and why it has none when it has
/// none.
///
/// An empty list alone cannot tell a server that answered with nothing from a
/// server that never answered: [live] with no item is a legitimate empty state,
/// [offline] is a missing connection.
enum DataAvailability {
  /// Nothing loaded yet.
  idle,

  /// A first read is in flight and there is nothing to show meanwhile.
  loading,

  /// The server answered.
  live,

  /// Served by the local mirror: as fresh as the last successful read.
  cached,

  /// The server could not be reached and nothing was mirrored — this data needs
  /// a connection.
  offline,

  /// The server answered and refused (4xx, 500).
  failed,
}

/// Availability tracking shared by [ApiCollection] and [ApiRecord] so the two
/// never drift.
///
/// The holder reports its reads ([beginRead], [resolveRead], [failRead]) and
/// gets back the verdict a screen renders on: [requiresConnection] to replace an
/// empty state with a connection notice, [isIncomplete] to warn that local data
/// is only part of the truth, [canWrite] to disable actions that would fail.
///
/// What the model itself allows comes from the same [ModelCapability] a
/// standalone widget resolves, so a button away from this screen and the screen
/// itself never disagree.
mixin DataAvailabilityState<T extends BaseModel<T>> {
  /// The resource being read — satisfied by the holder's own `api` field.
  ApiModel<T> get api;

  /// Whether the holder currently holds something to display.
  bool get hasData;

  /// Re-reads after a failed or degraded read, without a loader. Called when
  /// connectivity comes back.
  Future<void> healAvailability();

  /// Tells the listeners the verdict may have moved — the holder's own notify.
  void notifyAvailability();

  DataAvailability _availability = DataAvailability.idle;
  ModelCapability _capability = ModelCapability.unknown;
  bool _capabilityResolved = false;
  StreamSubscription<SyncStatusChangedEvent>? _availabilitySub;

  DataAvailability get availability => _availability;

  /// What the model allows away from the server, resolved on the first read.
  ModelCapability get capability => _capability;

  /// True when the last read could not reach the server and left nothing to
  /// show: the screen should say a connection is required rather than render an
  /// empty state.
  bool get requiresConnection => _availability == DataAvailability.offline;

  /// True when what is displayed comes from the local mirror.
  bool get isFromCache => _availability == DataAvailability.cached;

  /// True when the local mirror is known to hold only part of the model
  /// (`synchronizable_mode: partial`): what is displayed is what earlier reads
  /// happened to bring back, not everything the server has.
  bool get isIncomplete => isFromCache && _capability.isPartiallyMirrored;

  /// True when the last read had to degrade — it came from the mirror, or it
  /// could not happen at all.
  bool get isDegraded =>
      _availability == DataAvailability.cached ||
      _availability == DataAvailability.offline;

  /// Whether the server is answering, as both this holder's last read and the
  /// sync layer see it: a read may have degraded on a resource the connectivity
  /// stream still believes reachable, and connectivity may have dropped since
  /// the last successful read.
  bool get serverReachable => !isDegraded && SyncStatus.currentlyOnline;

  /// Whether an action on this data is worth offering — the same rule a
  /// standalone [ModelAvailability] applies.
  bool get canWrite => _capability.canWrite(serverReachable: serverReachable);

  /// Follows connectivity: heals a degraded holder when it comes back, and
  /// re-notifies otherwise since [canWrite] moves with it. The holder calls this
  /// from its constructor.
  void listenAvailability() {
    _availabilitySub = getService<Bus>().on<SyncStatusChangedEvent>().listen((
      event,
    ) {
      if (event.online && isDegraded) {
        healAvailability();
      } else {
        notifyAvailability();
      }
    });
  }

  void disposeAvailability() {
    _availabilitySub?.cancel();
    _availabilitySub = null;
  }

  /// Marks a read as started. Data already held stays displayed, and keeps its
  /// verdict until the new read settles.
  void beginRead() {
    if (!hasData) {
      _availability = DataAvailability.loading;
    }
  }

  void resolveRead({required bool fromCache}) => _availability = fromCache
      ? DataAvailability.cached
      : DataAvailability.live;

  void failRead(Object error) {
    if (!isServerUnavailable(error)) {
      _availability = DataAvailability.failed;

      return;
    }

    // What is already on screen is stale, not missing — a failed reload or a
    // failed page-two must not raise [requiresConnection], which promises the
    // holder has nothing to show.
    _availability = hasData
        ? DataAvailability.cached
        : DataAvailability.offline;
  }

  /// Reads what the model allows, once. A failure to resolve it — no metadata
  /// provider, or metadata unreachable offline — leaves [ModelCapability.unknown]
  /// and retries on the next read, rather than freezing a verdict on a payload
  /// that never arrived.
  Future<void> resolveModelFacts() async {
    if (_capabilityResolved) {
      return;
    }

    try {
      _capability = await api.capability();
      _capabilityResolved = true;
    } catch (_) {}
  }
}
