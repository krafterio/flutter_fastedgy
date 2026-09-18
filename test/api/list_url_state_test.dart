/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _ListScreen extends StatefulWidget {
  const _ListScreen();

  @override
  State<_ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<_ListScreen> with ListUrlState {
  @override
  void applyUrlState(Map<String, String> params, {required bool initial}) {}

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => writeUrl({'tab': 'pool'}),
          child: const Text('tab'),
        ),
        TextButton(
          onPressed: () => context.push('/items/1'),
          child: const Text('open'),
        ),
      ],
    );
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/items',
  routes: [
    GoRoute(
      path: '/items',
      builder: (context, state) => const Scaffold(body: _ListScreen()),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => const Scaffold(body: Text('detail')),
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('writeUrl puts the state in the url of the list it belongs to', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('tab'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/items?tab=pool');
  });

  testWidgets(
    'a write still pending when a page opens over the list leaves that page alone',
    (tester) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      await tester.tap(find.text('tab'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/items/1');
      expect(find.text('detail'), findsOneWidget);
    },
  );
}
