/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'list_support.dart';

/// Lets the reads started in the zone of the test land.
Future<void> _flush(WidgetTester tester) async {
  for (var turn = 0; turn < 20; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ThingApi api;

  setUp(() async {
    await setUpList();
    server = ThingServer();
    server.answer = (request) {
      final match = RegExp(r'/things/(\d+)/siblings$').firstMatch(request.path);

      if (match == null) {
        return null;
      }

      final id = int.parse(match[1]!);

      return MockResponse.json({'previous': id - 1, 'next': id + 1});
    };
    api = ThingApi(server.fetcher);
  });

  List<MockRequest> siblings() => [
    for (final request in server.requests)
      if (request.path.endsWith('/siblings')) request,
  ];

  test(
    'carries the filter and the order of the list a record is opened from',
    () async {
      final list = DataIterator<Thing>(
        api,
        filter: ['kind', '=', 1],
        defaultOrderBy: ['name:asc'],
      );

      expect(listContext(list), {
        'ctx': jsonEncode({
          'f': ['kind', '=', 1],
          'o': ['name:asc'],
        }),
      });
      expect(listContext(DataIterator<Thing>(api)), {'ctx': '{}'});

      list.dispose();
    },
  );

  group('the context of a record', () {
    late GoRouter router;
    late RecordContext record;

    Future<void> mount(WidgetTester tester, String location) async {
      var made = false;

      router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/w/:workspace/things/:id',
            builder: (context, state) {
              if (!made) {
                made = true;
                record = RecordContext.router(context, api);
              }

              return const SizedBox();
            },
          ),
        ],
      );

      await tester.pumpWidget(
        WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
      );
      await _flush(tester);
    }

    testWidgets(
      'gives the neighbours of the record in its list, and steps without stacking the history',
      (tester) async {
        final ctx = jsonEncode({
          'f': ['kind', '=', 1],
          'o': ['name:asc'],
        });

        await mount(tester, '/w/acme/things/7?ctx=${Uri.encodeComponent(ctx)}');

        expect(record.inList, isTrue);
        expect((record.previous, record.next), (6, 8));
        expect(record.status, SiblingsStatus.success);
        expect(siblings().single.queryParameters['order_by'], 'name:asc');
        expect(jsonDecode(siblings().single.headers['X-Filter'] as String), [
          'kind',
          '=',
          1,
        ]);

        record.go(record.next!);
        await _flush(tester);

        expect(router.state.uri.path, '/w/acme/things/8');
        expect(router.state.uri.queryParameters['ctx'], ctx);
        expect(router.canPop(), isFalse);
        expect((record.previous, record.next), (7, 9));

        getService<Bus>().fire(
          const ResourceChangedEvent(
            null,
            model: 'thing',
            type: ResourceChangeType.updated,
            id: 3,
          ),
        );
        // The watch listens from the zone of the build, outside the clock
        // of the test: its delay runs in real time.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await _flush(tester);

        expect(siblings(), hasLength(3));

        record.dispose();
      },
    );

    testWidgets('asks nothing when the record was not opened from a list', (
      tester,
    ) async {
      await mount(tester, '/w/acme/things/7');

      expect(record.inList, isFalse);
      expect(record.status, SiblingsStatus.idle);
      expect(siblings(), isEmpty);

      record.dispose();
    });
  });
}
