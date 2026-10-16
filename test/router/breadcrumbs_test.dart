/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _page(BuildContext context, GoRouterState state) => const SizedBox();

void main() {
  late GoRouter router;

  Future<List<Crumb>> crumbsAt(
    WidgetTester tester,
    String location, {
    bool push = false,
  }) async {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: _page),
        ShellRoute(
          builder: (context, state, child) => child,
          routes: [
            GoRoute(
              path: '/w/:workspace',
              builder: _page,
              routes: [
                GoRoute(
                  path: 'settings',
                  metadata: crumb((_) => 'Settings'),
                  builder: _page,
                ),
                GoRoute(
                  path: ':module',
                  metadata: crumb(
                    (parameters) => 'Module ${parameters['module']}',
                  ),
                  builder: _page,
                  routes: [
                    GoRoute(
                      path: ':id',
                      metadata: crumb((parameters) => '#${parameters['id']}'),
                      builder: _page,
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/account',
              metadata: crumb((_) => 'Account'),
              builder: _page,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
    );

    if (push) {
      router.go('/w/acme/settings');
      await tester.pumpAndSettle();
      unawaited(router.push(location));
    } else {
      router.go(location);
    }

    await tester.pumpAndSettle();

    return crumbsOf(router.routerDelegate.currentConfiguration);
  }

  testWidgets(
    'names a step per matched route that declares one, each leading back to where it matched',
    (tester) async {
      expect(await crumbsAt(tester, '/w/acme/tasks/12'), [
        (label: 'Module tasks', location: '/w/acme/tasks'),
        (label: '#12', location: '/w/acme/tasks/12'),
      ]);
    },
  );

  testWidgets('leaves out the routes that declare none', (tester) async {
    expect(await crumbsAt(tester, '/w/acme/settings'), [
      (label: 'Settings', location: '/w/acme/settings'),
    ]);
  });

  testWidgets('a page pushed over another keeps its own steps', (tester) async {
    expect(await crumbsAt(tester, '/account', push: true), [
      (label: 'Account', location: '/account'),
    ]);
  });
}
