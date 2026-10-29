/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The delegate of a [GoRouter], whose back button stops at a shell route
/// that left its navigator out of the tree, a list showing its detail in
/// place on a wide window: go_router reads the state of every shell
/// navigator of the location as if it were built.
class ShellBackRouterDelegate extends RouterDelegate<RouteMatchList> {
  ShellBackRouterDelegate(this._router);

  final GoRouterDelegate _router;

  @override
  void addListener(VoidCallback listener) => _router.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _router.removeListener(listener);

  @override
  RouteMatchList? get currentConfiguration => _router.currentConfiguration;

  @override
  Widget build(BuildContext context) => _router.build(context);

  @override
  Future<void> setNewRoutePath(RouteMatchList configuration) =>
      _router.setNewRoutePath(configuration);

  @override
  Future<void> setInitialRoutePath(RouteMatchList configuration) =>
      _router.setInitialRoutePath(configuration);

  @override
  Future<void> setRestoredRoutePath(RouteMatchList configuration) =>
      _router.setRestoredRoutePath(configuration);

  @override
  Future<bool> popRoute() async {
    final navigators = _builtNavigators();
    if (navigators == null) return _router.popRoute();

    for (final navigator in navigators.reversed) {
      if (await navigator.maybePop()) return true;
    }

    return false;
  }

  /// The navigators of the location down to its first shell navigator not
  /// built, null when go_router can walk them all itself.
  List<NavigatorState>? _builtNavigators() {
    final navigators = [?_router.navigatorKey.currentState];
    final matches = _router.currentConfiguration.matches;
    if (matches.isEmpty) return navigators;

    var walker = matches.last;
    while (walker is ShellRouteMatch) {
      final navigator = walker.navigatorKey.currentState;
      if (navigator == null) return navigators;

      final route = ModalRoute.of(navigator.context);
      if (route == null || !route.isCurrent) return null;

      navigators.add(navigator);
      walker = walker.matches.last;
    }

    return null;
  }
}
