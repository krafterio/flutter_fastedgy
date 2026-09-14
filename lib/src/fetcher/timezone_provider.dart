/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Provider of the device timezone, sent with every request as `X-Timezone`.
///
/// Registered and initialized by `initializeFastEdgy` before the Fetcher, so
/// the first request already carries it. It is read again each time the
/// application comes back to the foreground: a device that travelled has
/// changed zone.
///
/// To read it elsewhere, override [detect] and register the subclass in the
/// container before `initializeFastEdgy`, which then keeps it.
class TimezoneProvider with WidgetsBindingObserver {
  String? _timezone;
  bool _observing = false;

  /// The device timezone (e.g. 'Europe/Paris'), or null while it is unknown.
  String? getTimezone() => _timezone;

  /// Read the device timezone, then follow it across the app lifecycle.
  Future<void> initialize() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }

    await refresh();
  }

  /// Read the device timezone again, keeping the last one known when the
  /// platform can't tell.
  Future<void> refresh() async {
    _timezone = await detect() ?? _timezone;
  }

  /// The timezone of the device, or null when the platform can't tell.
  @protected
  Future<String?> detect() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  /// Forget the timezone read so far.
  void clearCache() {
    _timezone = null;
  }
}
