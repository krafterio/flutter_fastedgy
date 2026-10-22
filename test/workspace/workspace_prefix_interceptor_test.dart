/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart';

void main() {
  late List<String> sent;

  void fetcher({String? fallback}) {
    initializeContainer();
    container.registerSingleton<Bus>(Bus());
    container.registerSingleton<Fetcher>(
      createMockFetcher((request) {
        sent.add('${request.method} ${request.path}');

        return const MockResponse.json({'text': 'ok'});
      }, customInterceptors: [WorkspacePrefixInterceptor(fallback: fallback)]),
    );
  }

  setUp(() => sent = []);

  tearDown(container.reset);

  test(
    'sends a request under the fallback of an app without workspaces',
    () async {
      fetcher(fallback: 'h/default');

      await getService<Fetcher>().post(
        '/{workspace}/assistant/transcribe',
        null,
      );

      expect(sent, ['POST /h/default/assistant/transcribe']);
    },
  );

  test('refuses a request under a workspace an app without workspaces does not name', () async {
    fetcher();

    await expectLater(
      getService<Fetcher>().post('/{workspace}/assistant/transcribe', null),
      throwsA(isA<HttpError>()),
    );
    expect(sent, isEmpty);
  });
}
