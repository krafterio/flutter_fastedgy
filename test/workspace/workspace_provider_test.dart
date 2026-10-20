/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// What the shared corpus (workspaces_corpus_test.dart) cannot say: the timing
// of answers that cross, and what this package alone offers (loadRelated).

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Workspace extends BaseModel<_Workspace> {
  _Workspace(super.data);
}

/// Notes the current slug each time it reads what comes with the list.
class _Provider extends WorkspaceProvider<_Workspace> {
  _Provider() : super(_Workspace.new);

  final related = <String?>[];

  @override
  Future<void> loadRelated() async => related.add(slug);
}

Map<String, dynamic> _list(List<String> slugs) => {
  'items': [
    for (final (index, slug) in slugs.indexed) {'id': index + 1, 'slug': slug},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> sent;
  late FutureOr<MockResponse> Function(MockRequest) answer;
  late _Provider workspaces;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    initializeContainer();
    container.registerSingleton<Bus>(Bus());
    sent = [];
    answer = (request) => MockResponse.json(_list(['alpha', 'beta']));
    container.registerSingleton<Fetcher>(
      createMockFetcher((request) {
        sent.add('${request.method} ${request.path}');

        return answer(request);
      }, customInterceptors: [WorkspacePrefixInterceptor()]),
    );
    workspaces = container.registerSingleton<WorkspaceProvider>(
      _Provider(),
    ) as _Provider;
  });

  tearDown(container.reset);

  test('reads what comes with the list after each read of it, and for each '
      'workspace made current', () async {
    await workspaces.resolve(null);
    await pumpEventQueue();
    expect(workspaces.related, ['alpha']);

    await workspaces.resolve('beta');
    await pumpEventQueue();
    expect(workspaces.related, ['alpha', 'beta']);

    await workspaces.refresh();
    expect(workspaces.related, ['alpha', 'beta', 'beta']);
  });

  test(
    'reads what comes with a workspace adopted as the first one once',
    () async {
      answer = (request) => MockResponse.json(_list([]));
      await workspaces.load();
      await pumpEventQueue();

      answer = (request) => MockResponse.json(_list(['alpha']));
      workspaces.adopt(_Workspace({'id': 1, 'slug': 'alpha'}));
      await pumpEventQueue();

      expect(workspaces.related, [null, 'alpha']);
    },
  );

  test('reads the list once for requests answering 404 together', () async {
    await workspaces.resolve('alpha');
    await pumpEventQueue();
    answer = (request) => request.path == '/workspaces'
        ? MockResponse.json(_list(['alpha', 'beta']))
        : const MockResponse.error(404);
    sent.clear();

    final fetcher = getService<Fetcher>();

    await Future.wait([
      fetcher.get('/{workspace}/notes/1').then((_) {}, onError: (_) {}),
      fetcher.get('/{workspace}/notes/2').then((_) {}, onError: (_) {}),
    ]);
    await pumpEventQueue();

    expect(sent.where((request) => request == 'GET /workspaces'), hasLength(1));
  });

  test('drops a list read that answered for the account that left', () async {
    final leaving = Completer<MockResponse>();
    var reads = 0;

    answer = (request) =>
        reads++ == 0 ? leaving.future : MockResponse.json(_list(['gamma']));

    final first = workspaces.load();

    await pumpEventQueue();
    expect(sent, ['GET /workspaces']);

    getService<Bus>().fire(const AuthLogoutEvent());
    await pumpEventQueue();

    final opened = workspaces.load();

    leaving.complete(MockResponse.json(_list(['alpha'])));
    await Future.wait([first, opened]);
    await pumpEventQueue();

    expect(workspaces.slug, 'gamma');
    expect(workspaces.slugs, ['gamma']);
  });

  group('offline', () {
    test(
      'opens on the last list read when the server does not answer',
      () async {
        final store = container.registerSingleton<LocalStore>(
          DriftLocalStore(
            databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
          ),
        );
        await store.open();
        addTearDown(store.close);
        await workspaces.load();

        answer = (request) => const MockResponse.error(503);
        final reopened = _Provider();
        await reopened.load();

        expect(reopened.error, isNull);
        expect(reopened.slugs, ['alpha', 'beta']);
      },
    );

    test('keeps the failure without the offline layer', () async {
      answer = (request) => const MockResponse.error(503);
      await workspaces.load();

      expect(workspaces.error, isNotNull);
      expect(workspaces.slugs, isEmpty);
    });
  });
}
