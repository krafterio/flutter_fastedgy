/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late Fetcher fetcher;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    fetcher = createMockFetcher(
      (request) {
        requests.add(request);

        return const MockResponse.json({});
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );
  });

  test(
    'stamps every request with this instance, for the life of the process',
    () async {
      await fetcher.get('/things');
      await fetcher.get('/others');

      expect(requests.map((request) => request.headers[originHeader]), [
        originId,
        originId,
      ]);
    },
  );

  test('leaves a request the origin it names', () async {
    final origin = requestOrigin();

    await fetcher.post('/things', {}, headers: {originHeader: origin});

    expect(requests.single.headers[originHeader], origin);
  });

  test('draws a request origin of its own each time', () {
    final first = requestOrigin();
    final second = requestOrigin();

    expect(first, startsWith('$originId.'));
    expect(second, isNot(first));
    expect(first.length, lessThanOrEqualTo(64));
  });
}
