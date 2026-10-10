/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi({required Fetcher fetcher}) : super('/things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late _ThingApi api;
  Completer<void>? gate;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    gate = null;

    final fetcher = createMockFetcher(
      (request) async {
        requests.add(request);
        await gate?.future;

        final limit = int.parse('${request.queryParameters['limit']}');

        return MockResponse.json({
          'items': [
            for (var id = 1; id <= limit; id++) {'id': id},
          ],
          'total': 500,
          'limit': limit,
          'offset': request.queryParameters['offset'],
          'total_pages': (500 / limit).ceil(),
        });
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _ThingApi(fetcher: fetcher);
  });

  ({Object? offset, Object? limit}) window(MockRequest request) => (
    offset: request.queryParameters['offset'],
    limit: request.queryParameters['limit'],
  );

  test(
    'reads a page, every page up to one, or a range, in one request',
    () async {
      final things = ApiCollection<_Thing>(api, autoRefreshOnChange: false);
      const query = ListQuery(size: 50);

      await things.readPages(3, 3, query: query);
      expect((things.firstPage, things.page), (3, 3));

      await things.readPages(1, 3, query: query);
      expect((things.firstPage, things.page), (1, 3));

      await things.readPages(2, 4);
      expect((things.firstPage, things.page), (2, 4));

      expect(requests.map(window), [
        (offset: 100, limit: 50),
        (offset: 0, limit: 150),
        (offset: 50, limit: 150),
      ]);

      things.dispose();
    },
  );

  test('reads again the pages it holds, after a next page was added', () async {
    final things = ApiCollection<_Thing>(api, autoRefreshOnChange: false);

    await things.readPages(2, 2, query: const ListQuery(size: 50));
    await things.loadMore();
    await things.readPages(things.firstPage, things.page);

    expect(window(requests.last), (offset: 50, limit: 100));
    expect(things.items, hasLength(100));

    things.dispose();
  });

  test('forgets its rows on a reset, the read in flight and the changes announced meanwhile', () async {
    final things = ApiCollection<_Thing>(api);

    await things.readPages(1, 1, query: const ListQuery(size: 50));
    gate = Completer<void>();
    unawaited(things.readPages(2, 2));
    await pumpEventQueue();

    things.reset();
    gate!.complete();
    await pumpEventQueue();

    expect(things.items, isEmpty);
    expect(things.isLoaded, isFalse);
    expect(things.isLoading, isFalse);

    getService<Bus>().fire(const ResourcesStaleEvent());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(requests, hasLength(2));

    things.dispose();
  });
}
