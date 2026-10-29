/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<GoRouter> mount(WidgetTester tester, {required bool split}) async {
    final router = GoRouter(
      initialLocation: '/notes',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              split ? Text('Split ${state.uri}') : child,
          routes: [
            GoRoute(
              path: '/notes',
              builder: (context, state) => const Text('List'),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => const Text('Note'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      WidgetsApp.router(
        routerConfig: historyBackRouterConfig(router),
        color: const Color(0xFF000000),
      ),
    );
    router.go('/notes/12');
    await tester.pumpAndSettle();

    return router;
  }

  testWidgets(
    'the back button of a shell that left its navigator out leaves the page',
    (tester) async {
      await mount(tester, split: true);

      expect(await tester.binding.handlePopRoute(), isFalse);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Split /notes/12'), findsOneWidget);
    },
  );

  testWidgets('the back button of a built shell pops its detail', (
    tester,
  ) async {
    await mount(tester, split: false);
    expect(find.text('Note'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('List'), findsOneWidget);
  });
}
