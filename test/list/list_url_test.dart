/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('a url in memory', () {
    test(
      'writes the keys of one turn together, each list after its prefix',
      () async {
        final url = MemoryListUrl(
          initial: {'p': '2', 'done_p': '3', 'other': 'x'},
        );
        final done = url.withPrefix('done_');
        var told = 0;

        done.addListener(() => told++);

        expect(url.read(), {'p': '2', 'done_p': '3', 'other': 'x'});
        expect(done.read(), {'p': '3'});

        url.write({'p': null, 'q': 'lamp'});
        done.write({'q': 'desk', 'p': ''});
        await Future<void>.delayed(Duration.zero);

        expect(url.query, {'other': 'x', 'q': 'lamp', 'done_q': 'desk'});
        expect(told, 1);

        url.go({'other': 'y', 'q': 'lamp', 'done_q': 'desk'});

        expect(told, 1);
      },
    );
  });

  group('the url of the router', () {
    late GoRouter router;
    late ListUrl url;
    var made = false;

    Future<void> mount(WidgetTester tester) async {
      made = false;
      router = GoRouter(
        initialLocation: '/things?q=lamp',
        routes: [
          GoRoute(
            path: '/things',
            builder: (context, state) {
              if (!made) {
                made = true;
                url = ListUrl.router(context);
              }

              return const SizedBox();
            },
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
      );
    }

    testWidgets(
      'reads the query of its route, and replaces the location to write it',
      (tester) async {
        await mount(tester);

        expect(url.read(), {'q': 'lamp'});

        url.write({'q': 'desk', 'p': '2'});
        url.withPrefix('done_').write({'p': '3'});
        await tester.pumpAndSettle();

        expect(router.state.uri.queryParameters, {
          'q': 'desk',
          'p': '2',
          'done_p': '3',
        });
        expect(router.canPop(), isFalse);
      },
    );

    testWidgets(
      'tells a change from outside, and leaves alone a route shown over it',
      (tester) async {
        await mount(tester);
        final heard = <Map<String, String>>[];

        url.addListener(() => heard.add(url.read()));

        router.go('/things?q=chair');
        await tester.pumpAndSettle();

        expect(heard, [
          {'q': 'chair'},
        ]);

        router.push('/things/3?q=other');
        await tester.pumpAndSettle();
        url.write({'q': 'lost'});
        await tester.pumpAndSettle();

        expect(heard, hasLength(1));
        expect(url.read(), {'q': 'chair'});
        expect(router.state.uri.queryParameters, {'q': 'other'});
      },
    );
  });
}
