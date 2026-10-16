/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:go_router/go_router.dart';

/// The key of a route's metadata that names its step of the breadcrumb.
const crumbKey = 'crumb';

/// What a route gives the breadcrumb of the locations at or under it: its
/// label, from the parameters of the location.
typedef CrumbLabel = String Function(Map<String, String> parameters);

/// The metadata of a route that is a step of the breadcrumb:
/// `GoRoute(path: 'settings', metadata: crumb((_) => t('Settings')), …)`.
Map<String, Object> crumb(CrumbLabel label) => {crumbKey: label};

/// A step of the breadcrumb: its label, and the location it leads back to.
typedef Crumb = ({String label, String location});

/// The steps of [configuration] (a router's current one,
/// `router.routerDelegate.currentConfiguration`): one per matched route whose
/// metadata names one ([crumb]), from the root to the location shown. A page
/// pushed over another keeps its own steps, not those of the page under it.
List<Crumb> crumbsOf(RouteMatchList configuration) => _steps(configuration, []);

List<Crumb> _steps(RouteMatchList list, List<Crumb> crumbs) {
  for (final match in list.matches) {
    _step(match, list, crumbs);
  }

  return crumbs;
}

void _step(RouteMatchBase match, RouteMatchList list, List<Crumb> crumbs) {
  switch (match) {
    case ImperativeRouteMatch():
      crumbs.clear();
      _steps(match.matches, crumbs);
    case ShellRouteMatch():
      for (final inner in match.matches) {
        _step(inner, list, crumbs);
      }
    case RouteMatch():
      if (match.route.metadata?[crumbKey] case final CrumbLabel label) {
        crumbs.add((
          label: label(list.pathParameters),
          location: match.matchedLocation,
        ));
      }
    default:
      break;
  }
}
