/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:go_router/go_router.dart';

/// [location] carrying [current] as its `redirect`: the page to come back to
/// once [location] is done, a sign-in for one ([getRedirect]).
///
/// With [keepUrlRedirect], the `redirect` [current] already carries is passed
/// on instead, when it has one.
///
/// vue-fastedgy's `addRedirect`.
String addRedirect(
  Uri current,
  String location, {
  bool keepUrlRedirect = false,
}) {
  final uri = Uri.parse(location);
  final kept = keepUrlRedirect ? current.queryParameters['redirect'] : null;

  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'redirect': kept ?? '$current',
        },
      )
      .toString();
}

/// The page the `redirect` of [current] names ([addRedirect]), or [fallback].
///
/// Only a page of the app is followed: a `redirect` naming another site, or a
/// path that is not absolute, leads to [fallback].
///
/// vue-fastedgy's `getRedirect`.
String getRedirect(Uri current, String fallback) =>
    _readRedirect(current.queryParameters['redirect']) ?? fallback;

/// Whether [route] carries a `redirect`.
///
/// vue-fastedgy's `hasRedirect`.
bool hasRedirect(Uri route) => route.queryParameters.containsKey('redirect');

/// [location] without its `redirect`: its path, the rest of its query and its
/// fragment.
///
/// vue-fastedgy's `cleanRedirect`.
String cleanRedirect(String location) {
  final uri = Uri.parse('http://localhost/').resolve(location);

  if (!uri.queryParameters.containsKey('redirect')) {
    return Uri(
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  final query = {...uri.queryParametersAll}..remove('redirect');

  return Uri(
    path: uri.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

/// Goes to the page the `redirect` of [router]'s location names, cleaned of
/// its own ([cleanRedirect]); whether there was one ([getRedirect]).
///
/// vue-fastedgy's `redirectIfExist`.
bool redirectIfExist(GoRouter router) {
  final redirect = _readRedirect(router.state.uri.queryParameters['redirect']);

  if (redirect == null) {
    return false;
  }

  router.go(cleanRedirect(redirect));

  return true;
}

String? _readRedirect(String? redirect) {
  final uri = Uri.tryParse(redirect ?? '');

  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/')) {
    return null;
  }

  return '$uri';
}
