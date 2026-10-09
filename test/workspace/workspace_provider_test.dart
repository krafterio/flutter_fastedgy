/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// What the shared corpus (workspaces_corpus_test.dart) cannot say: the timing
// of answers that cross.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Workspace extends BaseModel<_Workspace> {
  _Workspace(super.data);
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
  late WorkspaceProvider<_Workspace> workspaces;

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
      WorkspaceProvider<_Workspace>(_Workspace.new),
    ) as WorkspaceProvider<_Workspace>;
  });

  tearDown(container.reset);

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
}
