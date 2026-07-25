/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import 'auth_events.dart';

/// Loads the authenticated user; the app supplies whichever call carries its
/// own user model (typically a `/me` resource service).
typedef UserLoader<TUser> = Future<TUser> Function();

/// Store of the authenticated user, shared by every screen that needs it.
///
/// Without it each screen calls `/me` on its own — three screens mounting
/// together issue three identical requests and then hold three copies that
/// drift apart as soon as one of them edits the profile. [load] is
/// single-flight: concurrent callers await the same request and read the same
/// instance, and [adopt] pushes an update to all of them at once.
///
/// The user model belongs to the app, so the store is registered by the app
/// rather than by `initializeFastEdgy`:
///
/// ```dart
/// container.registerSingleton<UserProvider<User>>(
///   UserProvider<User>(() => MeApi().getMe()),
/// );
///
/// final users = getService<UserProvider<User>>();
/// await users.load();
/// ```
///
/// A logout clears the store (via [AuthLogoutEvent]), so the next session
/// never reads the previous user.
class UserProvider<TUser> extends ChangeNotifier {
  final UserLoader<TUser> _loader;

  TUser? _user;
  bool _loaded = false;
  Object? _error;
  Future<TUser?>? _loading;

  /// Bumped by [clear]: a load started before a logout must not repopulate the
  /// store with the user that just left.
  int _generation = 0;

  UserProvider(this._loader, {Bus? bus}) {
    (bus ?? getService<Bus>()).on<AuthLogoutEvent>().listen((_) => clear());
  }

  /// The authenticated user, or null before the first successful [load].
  TUser? get user => _user;

  /// Whether a user has been loaded at least once.
  bool get isLoaded => _loaded;

  /// Whether a load is in flight.
  bool get loading => _loading != null;

  /// What the last [load] failed with, or null.
  Object? get error => _error;

  /// The authenticated user, loading it once when it is not held yet.
  ///
  /// Safe to call from every screen's `initState`: the calls that arrive while
  /// the first one is in flight await it instead of issuing their own.
  Future<TUser?> load() {
    final user = _user;

    return user != null ? Future.value(user) : refresh();
  }

  /// Reload from the server even when a user is already held (after a profile
  /// edit made elsewhere, a pull-to-refresh…), joining a load already running.
  ///
  /// [_run] never completes synchronously, so the assignment below always
  /// lands before the future clears it — a loader throwing on its first line
  /// included.
  Future<TUser?> refresh() => _loading ??= _run();

  Future<TUser?> _run() {
    final generation = _generation;

    return _load(generation).whenComplete(() {
      if (generation == _generation) {
        _loading = null;
      }

      notifyListeners();
    });
  }

  Future<TUser?> _load(int generation) async {
    try {
      final user = await _loader();

      // A logout landed while this was in flight: its result belongs to the
      // session that just ended.
      if (generation != _generation) {
        return null;
      }

      _user = user;
      _loaded = true;
      _error = null;

      return user;
    } catch (error) {
      if (generation == _generation) {
        _error = error;
      }

      rethrow;
    }
  }

  /// Adopt a user the caller already holds (the response of a profile update),
  /// so the screens refresh without a round trip.
  void adopt(TUser user) {
    _user = user;
    _loaded = true;
    _error = null;
    notifyListeners();
  }

  /// Forget the held user (logout).
  void clear() {
    _generation++;
    _user = null;
    _loaded = false;
    _error = null;
    _loading = null;
    notifyListeners();
  }
}
