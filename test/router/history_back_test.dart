/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

class _Browser extends UrlStrategy {
  _Browser(this.tester, String location) : entries = [(location, null)];

  final WidgetTester tester;
  final List<(String, Object?)> entries;
  var index = 0;
  final pushes = <String>[];
  var backs = 0;

  void report(Map<Object?, Object?> update) {
    final entry = ('${update['uri']}', update['state']);

    if (update['replace'] == true) {
      entries[index] = entry;
      return;
    }

    entries
      ..removeRange(index + 1, entries.length)
      ..add(entry);
    index++;
    pushes.add(entry.$1);
  }

  @override
  String getPath() => entries[index].$1;

  @override
  Object? getState() => {'serialCount': index.toDouble()};

  @override
  Future<void> go(int count) async {
    backs++;
    index += count;
    final (uri, state) = entries[index];
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {'location': uri, 'state': state}),
      ),
      (_) {},
    );
  }
}

void main() {
  late _Browser browser;
  late GoRouter router;

  Future<void> mount(WidgetTester tester, String location) async {
    browser = _Browser(tester, location);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          browser.report(call.arguments as Map<Object?, Object?>);
        }

        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
    GoRouter.optionURLReflectsImperativeAPIs = true;
    addTearDown(() => GoRouter.optionURLReflectsImperativeAPIs = false);
    router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/list',
          builder: (context, state) => const Text('List'),
          routes: [
            GoRoute(
              path: 'sheet',
              builder: (context, state) => const Text('Sheet'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      WidgetsApp.router(
        routerConfig: RouterConfig(
          routeInformationProvider: HistoryBackRouteInformationProvider(
            router.routeInformationProvider,
            strategy: browser,
          ),
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          backButtonDispatcher: router.backButtonDispatcher,
        ),
        color: const Color(0xFF000000),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'goes back to the entry it came from, and hands the result over',
    (tester) async {
      await mount(tester, '/list');

      final result = router.push<String>('/list/sheet');
      await tester.pumpAndSettle();
      router.pop('saved');
      await tester.pumpAndSettle();

      expect(await result, 'saved');
      expect(browser.pushes, ['/list/sheet']);
      expect(browser.backs, 1);
      expect(browser.getPath(), '/list');
      expect(router.state.uri.toString(), '/list');
      expect(find.text('List'), findsOneWidget);
    },
  );

  testWidgets('steps forward to a place the browser has not been before', (
    tester,
  ) async {
    await mount(tester, '/list/sheet');

    router.pop();
    await tester.pumpAndSettle();

    expect(browser.pushes, ['/list']);
    expect(browser.backs, 0);
    expect(router.state.uri.toString(), '/list');
  });
}
