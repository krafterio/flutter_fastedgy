/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'shell_back.dart';

final _configs = Expando<RouterConfig<RouteMatchList>>();

/// [router], whose way back to the previous entry of the browser history is
/// that entry rather than a new one, and whose back button stops at a shell
/// left out of the tree ([ShellBackRouterDelegate]).
RouterConfig<RouteMatchList> historyBackRouterConfig(GoRouter router) =>
    _configs[router] ??= RouterConfig(
      routeInformationProvider: HistoryBackRouteInformationProvider(
        router.routeInformationProvider,
      ),
      routeInformationParser: router.routeInformationParser,
      routerDelegate: ShellBackRouterDelegate(router.routerDelegate),
      backButtonDispatcher: router.backButtonDispatcher,
    );

/// Goes back in the browser history when the location reported is the one of
/// the previous entry, and reports to [_router] otherwise.
class HistoryBackRouteInformationProvider extends RouteInformationProvider {
  HistoryBackRouteInformationProvider(this._router, {UrlStrategy? strategy})
    : _strategy = strategy ?? urlStrategy;

  final RouteInformationProvider _router;
  final UrlStrategy? _strategy;
  final _locations = <int, String>{};

  @override
  RouteInformation get value => _router.value;

  @override
  void addListener(VoidCallback listener) => _router.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _router.removeListener(listener);

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    final strategy = _strategy;
    final entry = switch (strategy?.getState()) {
      {'serialCount': final num count} => count.toInt(),
      _ => null,
    };

    if (strategy == null || entry == null) {
      return _router.routerReportsNewRouteInformation(
        routeInformation,
        type: type,
      );
    }

    final here = _locations[entry] = strategy.getPath();
    final location = routeInformation.uri.toString();

    if (type != RouteInformationReportingType.neglect &&
        location != here &&
        _locations[entry - 1] == location) {
      unawaited(strategy.go(-1));
      return;
    }

    _router.routerReportsNewRouteInformation(routeInformation, type: type);

    if (type == RouteInformationReportingType.neglect) {
      _locations[entry] = location;
    }
  }
}
