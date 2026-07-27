/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';

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

  /// Rows the next response carries, and how many the server claims to hold.
  late List<Map<String, dynamic>> rows;
  late int total;

  /// Gates the next responses, in request order, so a test decides which one
  /// answers first. Counted from the call to [gate], not from the start of the
  /// test: reads made while setting the collection up must not shift them.
  List<Completer<void>>? gates;
  int gateCursor = 0;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    rows = [];
    total = 0;
    gates = null;
    gateCursor = 0;

    final fetcher = createMockFetcher(
      (request) async {
        requests.add(request);
        final pending = gates;

        if (pending != null && gateCursor < pending.length) {
          await pending[gateCursor++].future;
        }

        final limit = int.tryParse('${request.queryParameters['limit'] ?? ''}');

        return MockResponse.json({
          'items': limit == 0 ? [] : rows,
          'total': total,
          'limit': limit ?? rows.length,
          'offset': request.queryParameters['offset'] ?? 0,
          'total_pages': limit == null || limit == 0
              ? 1
              : (total / limit).ceil(),
        });
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _ThingApi(fetcher: fetcher);
  });

  ApiCollection<_Thing> collectionOf({
    dynamic fields,
    dynamic orderBy,
    int? limit,
    bool autoRefreshOnChange = true,
    Duration refreshDelay = const Duration(milliseconds: 10),
    Object? watchFields,
  }) {
    final collection = ApiCollection<_Thing>(
      api,
      fields: fields,
      orderBy: orderBy,
      limit: limit,
      autoRefreshOnChange: autoRefreshOnChange,
      refreshDelay: refreshDelay,
      watchFields: watchFields,
    );

    // Torn down here rather than at the end of each test: a failing expectation
    // would skip that line and leave the collection subscribed to the shared
    // bus, making the *next* test fail instead of this one.
    addTearDown(collection.dispose);

    return collection;
  }

  List<Completer<void>> gate(int count) {
    gateCursor = 0;

    return gates = [for (var i = 0; i < count; i++) Completer<void>()];
  }

  void seed(int count, {int? serverTotal}) {
    rows = [
      for (var i = 1; i <= count; i++) {'id': i, 'name': 'Row $i'},
    ];
    total = serverTotal ?? count;
  }

  group('merge', () {
    test('a new filter keeps the fields and the ordering', () async {
      seed(2);
      final collection = collectionOf(
        fields: ['id', 'name'],
        orderBy: 'name:asc',
        limit: 20,
      );
      await collection.load();

      await collection.refine(filter: ['name', '=', 'Row 1']);

      final last = requests.last;
      expect(last.headers['X-Fields'], 'id,name');
      expect(last.queryParameters['order_by'], 'name:asc');
      expect(last.headers['X-Filter'], '["name","=","Row 1"]');
    });

    test('a new ordering keeps a filter set earlier', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();
      await collection.refine(filter: ['name', '=', 'Row 1']);

      await collection.refine(orderBy: 'id:desc');

      expect(requests.last.headers['X-Filter'], '["name","=","Row 1"]');
      expect(requests.last.queryParameters['order_by'], 'id:desc');
    });

    test('an explicit null clears, an omitted argument does not', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();
      await collection.refine(filter: ['name', '=', 'Row 1']);

      await collection.refine(fields: ['id']);
      expect(requests.last.headers['X-Filter'], '["name","=","Row 1"]');

      await collection.refine(filter: null);
      expect(requests.last.headers.containsKey('X-Filter'), isFalse);
      expect(requests.last.headers['X-Fields'], 'id');
    });

    test('a cleared ordering falls back to the declared one', () async {
      seed(2);
      final collection = collectionOf(orderBy: 'name:asc', limit: 20);
      await collection.load();

      await collection.refine(orderBy: 'id:desc');
      expect(requests.last.queryParameters['order_by'], 'id:desc');

      await collection.refine(orderBy: null);
      expect(requests.last.queryParameters['order_by'], 'name:asc');
    });

    test('emits exactly one request whatever the number of parts', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();
      final before = requests.length;

      await collection.refine(
        filter: ['name', '=', 'x'],
        orderBy: 'id:desc',
        fields: ['id'],
        limit: 10,
      );

      expect(requests.length, before + 1);
    });

    test('a count-only read brings no row but the server total', () async {
      seed(3, serverTotal: 3);
      final collection = collectionOf(limit: 20);
      await collection.load();

      await collection.refine(limit: 0);

      expect(requests.last.queryParameters['limit'], 0);
      expect(collection.items, isEmpty);
      expect(collection.total, 3);
    });
  });

  group('page restore', () {
    test('a deep page costs one request over the whole range', () async {
      seed(60, serverTotal: 200);
      final collection = collectionOf(limit: 20);
      await collection.load();
      final before = requests.length;

      await collection.refine(orderBy: 'id:desc', page: 3);

      expect(requests.length, before + 1);
      expect(requests.last.queryParameters['limit'], 60);
      expect(requests.last.queryParameters['offset'], 0);
      expect(collection.page, 3);
      // The page size must survive a response whose own limit is the whole
      // range, or the next page would be read 60 rows at a time.
      expect(collection.limit, 20);
      expect(collection.totalPages, 10);
    });

    test('without a page size it can only read the first page', () async {
      seed(5);
      // Nothing was read yet, so there is no page size to multiply: the offset
      // of page 3 is not computable and asking for it must not be silently
      // answered with page 1's rows labelled page 3.
      final collection = collectionOf();

      await collection.refine(page: 3);

      expect(requests.last.queryParameters.containsKey('offset'), isFalse);
      expect(collection.page, 1);
    });
  });

  group('in flight', () {
    test('the rows and the total stay put until the response', () async {
      seed(2, serverTotal: 2);
      final collection = collectionOf(limit: 20);
      await collection.load();

      final held = gate(1);
      seed(1, serverTotal: 1);
      final pending = collection.refine(filter: ['name', '=', 'Row 1']);

      expect(collection.items.length, 2);
      expect(collection.total, 2);
      expect(collection.availability, DataAvailability.live);
      expect(collection.isLoading, isTrue);

      held[0].complete();
      await pending;

      expect(collection.items.length, 1);
      expect(collection.total, 1);
    });

    test('a response that lost the race is dropped', () async {
      seed(1, serverTotal: 1);
      final collection = collectionOf(limit: 20);
      await collection.load();

      // Two refines, the first answering last — what a search field typed
      // quickly produces.
      final held = gate(2);
      final first = collection.refine(filter: ['q', '=', 'a']);
      seed(3, serverTotal: 3);
      final second = collection.refine(filter: ['q', '=', 'ab']);

      held[1].complete();
      await second;
      expect(collection.items.length, 3);

      // The superseded read answers last, with rows nobody asked for anymore.
      seed(9, serverTotal: 9);
      held[0].complete();
      await first;

      expect(collection.items.length, 3);
      expect(collection.total, 3);
      expect(collection.isLoading, isFalse);
    });
  });

  group('sort', () {
    test('drives order_by and returns to the first page', () async {
      seed(60, serverTotal: 200);
      final collection = collectionOf(limit: 20);
      await collection.load();
      await collection.setPage(2);

      await collection.cycleSort('name');

      expect(requests.last.queryParameters['order_by'], 'name:asc');
      expect(requests.last.queryParameters['offset'], 0);
      expect(collection.page, 1);
      expect(collection.sort.keyFor('name')!.ascending, isTrue);
    });

    test('an emptied sort asks for no ordering at all', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();

      await collection.cycleSort('name');
      await collection.cycleSort('name');
      expect(requests.last.queryParameters['order_by'], 'name:desc');

      await collection.cycleSort('name');

      expect(collection.sort.isEmpty, isTrue);
      expect(requests.last.queryParameters.containsKey('order_by'), isFalse);
    });

    test('a multi-key sort sends every level, in order', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();

      await collection.cycleSort('status');
      await collection.cycleSort('name', additive: true);
      await collection.cycleSort('name', additive: true);

      expect(requests.last.queryParameters['order_by'], 'status:asc,name:desc');
    });

    test('an ordering passed by hand releases the header', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();
      await collection.cycleSort('name');

      await collection.refine(orderBy: 'id:desc');

      expect(collection.sort.isEmpty, isTrue);
    });
  });

  group('external changes', () {
    test('a deletion costs no request', () async {
      seed(3, serverTotal: 3);
      final collection = collectionOf(limit: 20);
      await collection.load();
      final before = requests.length;

      expect(collection.removeLocal(2), isTrue);

      expect(requests.length, before);
      expect(collection.items.map((row) => row.id), [1, 3]);
      expect(collection.total, 2);
      expect(collection.removeLocal(2), isFalse);
    });

    test('a collection opted out of auto-refresh ignores the bus', () async {
      seed(2);
      final collection = collectionOf(limit: 20, autoRefreshOnChange: false);
      await collection.load();
      final before = requests.length;

      getService<Bus>().fire(
        const ResourceChangedEvent('/things', type: ResourceChangeType.updated),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requests.length, before);
    });

    test('an opted-in collection still refreshes on the bus', () async {
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();
      final before = requests.length;

      getService<Bus>().fire(
        const ResourceChangedEvent('/things', type: ResourceChangeType.updated),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(requests.length, before + 1);
    });

    test('a burst of writes costs one re-read, not one each', () async {
      // A field saved on a timer fires an event per tick, and every list on
      // screen was re-reading its whole loaded range on each of them.
      seed(2);
      final collection = collectionOf(limit: 20);
      await collection.load();
      final before = requests.length;

      for (var tick = 0; tick < 5; tick++) {
        getService<Bus>().fire(
          const ResourceChangedEvent(
            '/things',
            type: ResourceChangeType.updated,
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(requests.length, before + 1);
    });

    test(
      'a write touching none of the fields it depends on is left alone',
      () async {
        seed(2);
        // It reads the description — a model replicated in part needs the
        // column — and does not depend on it. What it reads is no answer to
        // whether anything on screen would change.
        final collection = collectionOf(
          fields: ['id', 'name', 'description'],
          watchFields: ['id', 'name'],
          limit: 20,
        );
        await collection.load();
        final before = requests.length;

        getService<Bus>().fire(
          const ResourceChangedEvent(
            '/things',
            type: ResourceChangeType.updated,
            fields: {'description'},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(requests.length, before);
      },
    );

    test('a write touching one of them is read', () async {
      seed(2);
      final collection = collectionOf(
        fields: ['id', 'name'],
        watchFields: true,
        limit: 20,
      );
      await collection.load();
      final before = requests.length;

      getService<Bus>().fire(
        const ResourceChangedEvent(
          '/things',
          type: ResourceChangeType.updated,
          fields: {'name'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(requests.length, before + 1);
    });

    test('a row appearing is read whatever the fields say', () async {
      seed(2);
      final collection = collectionOf(
        fields: ['id', 'name'],
        watchFields: true,
        limit: 20,
      );
      await collection.load();
      final before = requests.length;

      getService<Bus>().fire(
        const ResourceChangedEvent(
          '/things',
          type: ResourceChangeType.created,
          fields: {'description'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(requests.length, before + 1);
    });
  });
}
