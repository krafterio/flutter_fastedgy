/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../container/container.dart';

/// Live switch of the local half of the offline layer: the record mirror and
/// the buffered writes.
///
/// Registered by `initializeFastEdgy(offline: true)` and read on every call, so
/// an application whose entitlement changes mid-session (a plan, a policy)
/// flips without a restart. Disabled, an `ApiModel` reads and writes over the
/// network as if the module were absent, while the resource cache, the sync
/// status and the replay of an already buffered queue keep working.
class OfflineMode extends ChangeNotifier {
  bool _enabled;

  OfflineMode({this._enabled = true});

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (value == _enabled) {
      return;
    }

    _enabled = value;
    notifyListeners();
  }

  /// Whether the local layer may answer, readable without holding the service:
  /// an application that registered none is never gated.
  static bool get isEnabled =>
      !hasService<OfflineMode>() || getService<OfflineMode>().enabled;
}
