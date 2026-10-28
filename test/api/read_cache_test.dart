/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);

  String? get name => getString('name');
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
  var name = 'Ranger le garage';

  setUp(() async {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    await ReadCache.clear();
    requests = [];
    name = 'Ranger le garage';

    final fetcher = createMockFetcher(
      (request) async {
        requests.add(request);

        if (request.path.endsWith('/things/1')) {
          return MockResponse.json({'id': 1, 'name': name});
        }

        return MockResponse.json({
          'items': [
            {'id': 1, 'name': name},
          ],
          'total': 1,
          'limit': 50,
          'offset': 0,
        });
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _ThingApi(fetcher: fetcher);
  });

  ApiCollection<_Thing> collection({
    Duration staleAfter = const Duration(minutes: 5),
  }) => ApiCollection<_Thing>(
    api,
    autoRefreshOnChange: false,
    cacheKey: 'home',
    staleAfter: staleAfter,
  );

  const query = ListQuery(filter: ['name', '=', 'garage']);

  group('a cached collection', () {
    test('reads the network once, then shows the rows it kept without reading again while they are fresh', () async {
      final first = collection();
      await first.loadCached(query: query);
      first.dispose();
      expect(requests, hasLength(1));

      final again = collection();
      final shown = <bool>[];
      again.addListener(() => shown.add(again.isLoading));
      await again.loadCached(query: query);

      expect(again.items.single.name, 'Ranger le garage');
      expect(
        shown,
        isNot(contains(true)),
        reason: 'no loader for what is kept',
      );
      expect(requests, hasLength(1), reason: 'fresh, nothing read again');
      again.dispose();
    });

    test(
      'shows the kept rows at once and reads them again behind once stale',
      () async {
        await collection().loadCached(query: query);
        name = 'Vider le garage';

        final again = collection(staleAfter: Duration.zero);
        final future = again.loadCached(query: query);
        await Future<void>.delayed(Duration.zero);
        expect(
          again.items.single.name,
          'Ranger le garage',
          reason: 'the kept rows first',
        );

        await future;
        expect(again.items.single.name, 'Vider le garage');
        expect(requests, hasLength(2));
      },
    );

    test('reads again when forced, and keeps another query apart', () async {
      await collection().loadCached(query: query);

      await collection().loadCached(query: query, force: true);
      expect(requests, hasLength(2));

      await collection().loadCached(
        query: const ListQuery(filter: ['name', '=', 'cave']),
      );
      expect(
        requests,
        hasLength(3),
        reason: 'another query, nothing kept for it',
      );
    });

    test('forgets everything once cleared', () async {
      await collection().loadCached(query: query);
      await ReadCache.clear();

      await collection().loadCached(query: query);
      expect(requests, hasLength(2));
    });
  });

  test('a cached record shows what it kept without reading again while it is fresh', () async {
    final first = ApiRecord<_Thing>(api, cacheKey: 'home');
    await first.loadCached(1);
    first.dispose();

    final again = ApiRecord<_Thing>(api, cacheKey: 'home');
    await again.loadCached(1);

    expect(again.value?.name, 'Ranger le garage');
    expect(requests, hasLength(1));
    again.dispose();
  });
}
