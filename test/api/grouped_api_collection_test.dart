/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';

import '../helpers/fake_metadata.dart';

class _Flow extends BaseModel<_Flow> {
  _Flow(super.data);
}

class _FlowApi extends ApiModel<_Flow> {
  _FlowApi({required Fetcher fetcher})
    : super('/{workspace}', modelName: 'flow', fetcher: fetcher);

  @override
  _Flow fromJson(Map<String, dynamic> json) => _Flow(json);
}

/// The rule a request's X-Filter narrows to, as `field=value` (`status=3`,
/// `priority=low`, `status=empty`), so a test can say which bucket it belongs to.
String? bucketOf(MockRequest request) {
  final raw = request.headers['X-Filter'] as String?;

  if (raw == null) {
    return null;
  }

  List<Object?> leaf(Object? node) {
    final list = node as List<Object?>;

    if (list.first == '&' || list.first == '|') {
      final rules = list[1] as List<Object?>;

      return leaf(rules.last);
    }

    return list;
  }

  final rule = leaf(jsonDecode(raw) as List<Object?>);

  return '${rule.first}=${rule.length > 2 ? rule[2] : 'empty'}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late _FlowApi api;

  /// Rows per bucket, and the server total each bucket reports.
  late Map<String, List<Map<String, dynamic>>> rowsByBucket;
  late Map<String, int> totalByBucket;

  /// Buckets whose read fails with a server that is not answering.
  late Set<String> unreachable;

  /// Target records of the many2one axis.
  late List<Map<String, dynamic>> statuses;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    container.registerSingleton<MetadataProvider>(fakeMetadataProvider());

    requests = [];
    unreachable = {};
    statuses = [
      {'id': 3, 'name': 'To do'},
      {'id': 7, 'name': 'Doing'},
    ];
    rowsByBucket = {
      'status=3': [
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'},
      ],
      'status=7': [
        {'id': 3, 'name': 'C'},
      ],
      'status=empty': [],
      'priority=low': [
        {'id': 4, 'name': 'D'},
      ],
      'priority=normal': [
        {'id': 5, 'name': 'E'},
      ],
    };
    totalByBucket = {'status=3': 40, 'status=7': 1, 'status=empty': 0};

    final fetcher = createMockFetcher(
      (request) {
        requests.add(request);
        final limit =
            int.tryParse('${request.queryParameters['limit'] ?? ''}') ?? 20;
        final offset =
            int.tryParse('${request.queryParameters['offset'] ?? ''}') ?? 0;

        if (request.path.endsWith('/flow_statuses')) {
          return MockResponse.json({
            'items': statuses.skip(offset).take(limit).toList(),
            'total': statuses.length,
            'limit': limit,
            'offset': offset,
            'total_pages': (statuses.length / limit).ceil(),
          });
        }

        final bucket = bucketOf(request) ?? '';

        if (unreachable.contains(bucket)) {
          return const MockResponse.error(503);
        }

        final rows = rowsByBucket[bucket] ?? const [];
        final total = totalByBucket[bucket] ?? rows.length;

        return MockResponse.json({
          'items': rows,
          'total': total,
          'limit': limit,
          'offset': offset,
          'total_pages': (total / limit).ceil(),
        });
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _FlowApi(fetcher: fetcher);
  });

  tearDown(() => container.unregister<MetadataProvider>());

  Future<GroupedApiCollection<_Flow>> grouped(
    String field, {
    Object? filter,
    int rowLimit = 20,
    int groupLimit = 20,
    Duration refreshDelay = const Duration(milliseconds: 10),
  }) async {
    final source = await resolveGroupSource(
      api,
      field,
      emptyLabel: 'None',
      limit: groupLimit,
    );
    final collection = GroupedApiCollection<_Flow>(
      api,
      source!,
      fields: const ['id', 'name'],
      filter: filter,
      rowLimit: rowLimit,
      refreshDelay: refreshDelay,
    );
    addTearDown(collection.dispose);

    return collection;
  }

  List<MockRequest> rowRequests() =>
      requests.where((r) => !r.path.endsWith('/flow_statuses')).toList();

  group('fan out', () {
    test('a many2one axis costs one request plus one per bucket', () async {
      final collection = await grouped('status');

      await collection.load();

      expect(requests.length, 4);
      expect(requests.first.path, '/{workspace}/flow_statuses');
      expect(rowRequests().map(bucketOf), [
        'status=3',
        'status=7',
        'status=empty',
      ]);
    });

    test('a choice axis costs only the bucket requests', () async {
      final collection = await grouped('priority');

      await collection.load();

      // Five buckets (four values + no value), no axis request at all.
      expect(requests.length, 5);
      expect(requests.map(bucketOf).whereType<String>().length, 5);
    });

    test('every request goes to the model, never to some aggregate', () async {
      final collection = await grouped('status');

      await collection.load();

      for (final request in rowRequests()) {
        expect(request.path, '/{workspace}/flows');
        expect(request.method, 'GET');
      }
    });

    test('each bucket carries its own total, from its own response', () async {
      final collection = await grouped('status');

      await collection.load();

      final totals = {
        for (final entry in collection.entries)
          entry.group.label: entry.collection.total,
      };

      expect(totals, {'To do': 40, 'Doing': 1, 'None': 0});
      expect(collection.entries.first.collection.totalPages, 2);
    });

    test('the list filter is ANDed with the bucket rule', () async {
      final collection = await grouped(
        'status',
        filter: ['name', 'icontains', 'a'],
      );

      await collection.load();

      final filter = jsonDecode(
        rowRequests().first.headers['X-Filter'] as String,
      ) as List<Object?>;

      expect(filter.first, '&');
      expect(filter[1], [
        ['name', 'icontains', 'a'],
        ['status', '=', 3],
      ]);
    });
  });

  group('pagination', () {
    test('turning one bucket touches no other', () async {
      final collection = await grouped('status');
      await collection.load();
      final before = requests.length;

      await collection.entries.first.collection.nextPage();

      final added = requests.sublist(before);
      expect(added.length, 1);
      expect(bucketOf(added.single), 'status=3');
      expect(added.single.queryParameters['offset'], 20);
      expect(collection.entries[1].collection.page, 1);
    });

    test('a bucket the axis kept is reused, page and all', () async {
      // Three buckets per axis page: [To do, Doing, None].
      final collection = await grouped('status', groupLimit: 3);
      await collection.load();

      await collection.entries.first.collection.nextPage();
      final kept = collection.entries.first.collection;
      expect(kept.page, 2);

      // A status is inserted before it: every bucket shifts one rank down,
      // "To do" among them.
      statuses = [
        {'id': 1, 'name': 'Backlog'},
        ...statuses,
      ];
      rowsByBucket['status=1'] = [
        {'id': 9, 'name': 'Z'},
      ];
      final before = requests.length;
      await collection.setGroupPage(1);

      expect(collection.entries.map((entry) => entry.group.key), [
        'id:1',
        'id:3',
        'id:7',
        'empty',
      ]);
      // Rebuilt from scratch it would be back on page 1, and the rows the user
      // had scrolled to would be gone.
      expect(identical(collection.entries[1].collection, kept), isTrue);
      expect(collection.entries[1].collection.page, 2);
      // The axis, plus the one bucket that is actually new.
      expect(requests.length - before, 2);
      expect(bucketOf(requests.last), 'status=1');
    });

    test('a bucket that left the axis is disposed', () async {
      final collection = await grouped('status');
      await collection.load();
      // The bucket of a status that goes away — not the empty one, whose key
      // survives any change to the axis.
      final dropped = collection.entries[1].collection;

      statuses = [
        {'id': 3, 'name': 'To do'},
      ];
      await collection.setGroupPage(1);

      expect(collection.entries.map((entry) => entry.group.key), [
        'id:3',
        'empty',
      ]);
      expect(() => dropped.addListener(() {}), throwsFlutterError);
    });
  });

  group('mutations', () {
    test('a deletion costs no request', () async {
      final collection = await grouped('status');
      await collection.load();
      final before = requests.length;

      getService<Bus>().fire(
        const ResourceChangedEvent(
          '/{workspace}/flows',
          type: ResourceChangeType.deleted,
          id: 1,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(requests.length, before);
      expect(collection.entries.first.collection.items.map((row) => row.id), [
        2,
      ]);
      expect(collection.entries.first.collection.total, 39);
    });

    test('a burst of writes collapses into one salvo', () async {
      final collection = await grouped('status');
      await collection.load();
      final before = requests.length;

      for (var i = 0; i < 3; i++) {
        getService<Bus>().fire(
          const ResourceChangedEvent(
            '/{workspace}/flows',
            type: ResourceChangeType.created,
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // One read per visible bucket, once — not three rounds of them.
      expect(requests.length - before, 3);
    });

    test(
      'every visible bucket is re-read, not only the one holding the id',
      () async {
        final collection = await grouped('status');
        await collection.load();
        final before = requests.length;

        getService<Bus>().fire(
          const ResourceChangedEvent(
            '/{workspace}/flows',
            type: ResourceChangeType.updated,
            id: 1,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // A record whose status changed left one bucket for another, and which
        // one it landed in cannot be known from here.
        expect(requests.sublist(before).map(bucketOf), [
          'status=3',
          'status=7',
          'status=empty',
        ]);
      },
    );

    test('a change on the axis model reloads the axis', () async {
      final collection = await grouped('status');
      await collection.load();
      statuses = [
        {'id': 3, 'name': 'To do'},
        {'id': 7, 'name': 'Doing'},
        {'id': 9, 'name': 'Done'},
      ];

      getService<Bus>().fire(
        const ResourceChangedEvent(
          '/{workspace}/flow_statuses',
          type: ResourceChangeType.created,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(collection.entries.map((entry) => entry.group.label), [
        'To do',
        'Doing',
        'Done',
        'None',
      ]);
    });
  });

  group('notifications', () {
    test('the buckets are coalesced into a rebuild or two', () async {
      final collection = await grouped('status');
      var notifications = 0;
      collection.addListener(() => notifications++);

      await collection.load();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Three buckets raise a dozen raw notifications between them, across as
      // many await points: a screen rebuilds twice — once loading, once done.
      expect(notifications, 2);
    });
  });

  group('sort', () {
    test('applies inside every bucket', () async {
      final collection = await grouped('status');
      await collection.load();
      final before = requests.length;

      await collection.cycleSort('name');

      final added = requests.sublist(before);
      expect(added.length, 3);
      for (final request in added) {
        expect(request.queryParameters['order_by'], 'name:asc');
        expect(request.queryParameters['offset'], 0);
      }
      expect(collection.sort.keyFor('name')!.ascending, isTrue);
    });
  });

  group('availability', () {
    test('one failing bucket is not a screen needing a connection', () async {
      unreachable = {'status=7'};
      final collection = await grouped('status');

      await collection.load();

      expect(collection.requiresConnection, isFalse);
      expect(collection.entries[1].collection.requiresConnection, isTrue);
      expect(collection.entries.first.collection.hasData, isTrue);
    });

    test('one failing bucket among empty ones is still not', () async {
      // Nothing on screen anywhere, so the rows cannot vouch for the verdict:
      // it rests on the buckets that *did* answer, and two of them did.
      rowsByBucket['status=3'] = [];
      totalByBucket['status=3'] = 0;
      unreachable = {'status=7'};
      final collection = await grouped('status');

      await collection.load();

      expect(collection.hasData, isFalse);
      expect(collection.requiresConnection, isFalse);
      expect(collection.isEmpty, isTrue);
    });

    test('every bucket failing is', () async {
      unreachable = {'status=3', 'status=7', 'status=empty'};
      final collection = await grouped('status');

      await collection.load();

      expect(collection.requiresConnection, isTrue);
      expect(collection.hasData, isFalse);
    });

    test('an unreadable axis is, with no bucket at all', () async {
      unreachable = {''};
      final offline = createMockFetcher(
        (request) => const MockResponse.error(503),
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      );
      final source = await resolveGroupSource(
        _FlowApi(fetcher: offline),
        'status',
      );
      final collection = GroupedApiCollection<_Flow>(api, source!);
      addTearDown(collection.dispose);

      await collection.load();

      expect(collection.entries, isEmpty);
      expect(collection.requiresConnection, isTrue);
    });

    test('an empty bucket next to filled ones is an empty state', () async {
      final collection = await grouped('status');

      await collection.load();

      final none = collection.entries.last.collection;
      expect(none.isEmpty, isTrue);
      expect(none.requiresConnection, isFalse);
      expect(collection.isEmpty, isFalse);
    });
  });
}
