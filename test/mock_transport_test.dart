/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  tearDown(container.reset);

  test('answers a request from the responder, decoded as JSON', () async {
    final seen = <MockRequest>[];
    final fetcher = createMockFetcher((request) {
      seen.add(request);

      return const MockResponse.json({'id': 1, 'name': 'Ada'});
    }, enableAuth: false);

    final response = await fetcher.get('/me', params: {'limit': 2});

    expect(response.data, {'id': 1, 'name': 'Ada'});
    expect(seen.single.method, 'GET');
    expect(seen.single.path, '/me');
    expect(seen.single.queryParameters, {'limit': 2});
  });

  test('carries the payload of a write to the responder', () async {
    MockRequest? seen;
    final fetcher = createMockFetcher((request) {
      seen = request;

      return const MockResponse.empty();
    }, enableAuth: false);

    await fetcher.post('/projects', {'name': 'Blum'});

    expect(seen?.method, 'POST');
    expect(seen?.body, {'name': 'Blum'});
  });

  test('maps a scripted refusal to an HttpError of that status', () async {
    final fetcher = createMockFetcher(
      (request) => const MockResponse.error(404, body: {'detail': 'Not found'}),
      enableAuth: false,
    );

    await expectLater(
      fetcher.get('/projects/9'),
      throwsA(
        isA<HttpError>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'Not found'),
      ),
    );
  });
}
