/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _page(BuildContext context, GoRouterState state) => const SizedBox();

Future<GoRouter> _routerAt(WidgetTester tester, String location) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/', builder: _page),
      GoRoute(path: '/login', builder: _page),
      GoRoute(path: '/w/:workspace/notes', builder: _page),
    ],
  );
  await tester.pumpWidget(
    WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
  );
  await tester.pumpAndSettle();

  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('addRedirect', () {
    test('carries the page, its query included', () {
      expect(
        addRedirect(Uri.parse('/w/acme/notes/12?list=3'), '/login'),
        '/login?redirect=%2Fw%2Facme%2Fnotes%2F12%3Flist%3D3',
      );
    });

    test('passes on the redirect the page carries, when asked to', () {
      final current = Uri.parse('/register?redirect=%2Fw%2Facme');

      expect(
        addRedirect(current, '/login', keepUrlRedirect: true),
        '/login?redirect=%2Fw%2Facme',
      );
      expect(
        addRedirect(Uri.parse('/register'), '/login', keepUrlRedirect: true),
        '/login?redirect=%2Fregister',
      );
    });

    test('keeps the query of the location', () {
      expect(
        addRedirect(Uri.parse('/w/acme'), '/login?mode=short'),
        '/login?mode=short&redirect=%2Fw%2Facme',
      );
    });
  });

  group('getRedirect', () {
    test('reads back the page addRedirect carries', () {
      final current = Uri.parse('/w/acme/notes/12?list=3');

      expect(
        getRedirect(Uri.parse(addRedirect(current, '/login')), '/'),
        '/w/acme/notes/12?list=3',
      );
    });

    test('falls back without a redirect', () {
      expect(getRedirect(Uri.parse('/login'), '/home'), '/home');
    });

    test('follows only a page of the app', () {
      for (final redirect in [
        'https://example.com/w/acme',
        '//example.com/w/acme',
        'w/acme',
        '',
      ]) {
        final current = Uri(
          path: '/login',
          queryParameters: {'redirect': redirect},
        );

        expect(getRedirect(current, '/'), '/', reason: redirect);
      }
    });
  });

  test('hasRedirect tells a location carrying one', () {
    expect(hasRedirect(Uri.parse('/login?redirect=%2Fw%2Facme')), isTrue);
    expect(hasRedirect(Uri.parse('/login')), isFalse);
  });

  group('cleanRedirect', () {
    test('removes the redirect of a location and keeps the rest', () {
      expect(
        cleanRedirect('/w/acme/notes?list=3&redirect=%2Faccount#top'),
        '/w/acme/notes?list=3#top',
      );
    });

    test('keeps a location without redirect as it is', () {
      expect(cleanRedirect('/w/acme/notes?list=3'), '/w/acme/notes?list=3');
    });

    test('answers a path of the app', () {
      expect(cleanRedirect('https://example.com/w/acme'), '/w/acme');
      expect(cleanRedirect('//example.com/w/acme'), '/w/acme');
    });
  });

  group('redirectIfExist', () {
    testWidgets('goes to the redirect, cleaned of its own', (tester) async {
      final router = await _routerAt(
        tester,
        addRedirect(Uri.parse('/w/acme/notes?list=3&redirect=%2F'), '/login'),
      );

      expect(redirectIfExist(router), isTrue);
      await tester.pumpAndSettle();

      expect(_location(router), '/w/acme/notes?list=3');
    });

    testWidgets('stays for a redirect that is no page of the app', (
      tester,
    ) async {
      final router = await _routerAt(
        tester,
        '/login?redirect=https%3A%2F%2Fexample.com%2Fw%2Facme%2Fnotes',
      );

      expect(redirectIfExist(router), isFalse);
      await tester.pumpAndSettle();

      expect(
        _location(router),
        '/login?redirect=https%3A%2F%2Fexample.com%2Fw%2Facme%2Fnotes',
      );
    });

    testWidgets('stays without redirect', (tester) async {
      final router = await _routerAt(tester, '/login');

      expect(redirectIfExist(router), isFalse);
    });
  });
}
