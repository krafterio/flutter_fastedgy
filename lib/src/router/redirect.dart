/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// [location] carrying [current] as its `redirect`: the page to come back to
/// once [location] is done, a sign-in for one ([getRedirect]).
///
/// vue-fastedgy's `addRedirect`.
String addRedirect(Uri current, String location) {
  final uri = Uri.parse(location);

  return uri
      .replace(
        queryParameters: {...uri.queryParameters, 'redirect': '$current'},
      )
      .toString();
}

/// The page the `redirect` of [current] names ([addRedirect]), or [fallback].
///
/// Only a page of the app is followed: a `redirect` naming another site, or a
/// path that is not absolute, leads to [fallback].
///
/// vue-fastedgy's `getRedirect`.
String getRedirect(Uri current, String fallback) {
  final redirect = Uri.tryParse(current.queryParameters['redirect'] ?? '');

  if (redirect == null ||
      redirect.hasScheme ||
      redirect.hasAuthority ||
      !redirect.path.startsWith('/')) {
    return fallback;
  }

  return '$redirect';
}
