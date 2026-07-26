/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';

import '../helpers/fake_metadata.dart';

class _Flow extends BaseModel<_Flow> {
  _Flow(super.data);
}

class _FlowApi extends ApiModel<_Flow> {
  _FlowApi({required Fetcher fetcher, String model = 'flow'})
    : super('/{workspace}', modelName: model, fetcher: fetcher);

  @override
  _Flow fromJson(Map<String, dynamic> json) => _Flow(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late _FlowApi api;

  /// Target records the next axis read returns, and the server total.
  late List<Map<String, dynamic>> statuses;
  late int statusTotal;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    container.registerSingleton<MetadataProvider>(fakeMetadataProvider());

    requests = [];
    statuses = [
      {'id': 3, 'name': 'To do'},
      {'id': 7, 'name': 'In progress'},
    ];
    statusTotal = 2;

    final fetcher = createMockFetcher(
      (request) {
        requests.add(request);
        final limit =
            int.tryParse('${request.queryParameters['limit'] ?? ''}') ?? 20;
        final offset =
            int.tryParse('${request.queryParameters['offset'] ?? ''}') ?? 0;
        final page = statuses.skip(offset).take(limit).toList();

        return MockResponse.json({
          'items': page,
          'total': statusTotal,
          'limit': limit,
          'offset': offset,
          'total_pages': (statusTotal / limit).ceil(),
        });
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _FlowApi(fetcher: fetcher);
  });

  tearDown(() => container.unregister<MetadataProvider>());

  group('choice axis', () {
    test('costs no request at all', () async {
      final source = await resolveGroupSource(api, 'priority');
      addTearDown(source!.dispose);

      await source.load();

      // The enum came with the metadata: asking the server for it would be a
      // request for something already in memory.
      expect(requests, isEmpty);
      expect(source.groups.length, 5);
    });

    test('keeps the order the server declared, empty bucket last', () async {
      final source = await resolveGroupSource(
        api,
        'priority',
        emptyLabel: 'None',
      );
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.map((group) => group.label), [
        'low',
        'normal',
        'high',
        'critical',
        'None',
      ]);
      expect(source.groups.last.isEmptyBucket, isTrue);
    });

    test('produces the filter rule of each bucket', () async {
      final source = await resolveGroupSource(api, 'priority');
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.first.predicate, ['priority', '=', 'low']);
      expect(source.groups.last.predicate, ['priority', 'is empty']);
    });

    test('a required field has no empty bucket', () async {
      final source = await resolveGroupSource(
        _FlowApi(fetcher: api.fetcher, model: 'user'),
        'role',
      );
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.length, 2);
      expect(source.groups.any((group) => group.isEmptyBucket), isFalse);
      expect(source.total, 2);
    });

    test('paginates in memory', () async {
      final source = await resolveGroupSource(api, 'priority', limit: 2);
      addTearDown(source!.dispose);
      await source.load();

      expect(source.totalPages, 3);
      expect(source.groups.map((group) => group.value), ['low', 'normal']);

      await source.setPage(3);

      expect(source.groups.map((group) => group.value), [null]);
      expect(source.hasNextPage, isFalse);
      expect(requests, isEmpty);
    });

    test('a value hook decides what the rule compares to', () async {
      final source = await resolveGroupSource(
        api,
        'priority',
        valueOf: (key) => key.toUpperCase(),
        labelOf: (key, label) => 'P: $label',
      );
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.first.predicate, ['priority', '=', 'LOW']);
      expect(source.groups.first.label, 'P: low');
    });
  });

  group('relation axis', () {
    test('reads the target model once, as a paginated list', () async {
      final source = await resolveGroupSource(api, 'status', limit: 10);
      addTearDown(source!.dispose);

      await source.load();

      expect(requests.length, 1);
      expect(requests.single.path, '/{workspace}/flow_statuses');
      expect(requests.single.queryParameters['limit'], 10);
      expect(requests.single.headers['X-Fields'], 'id,name');
    });

    test('names each bucket after the target label field', () async {
      final source = await resolveGroupSource(api, 'status');
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.map((group) => group.label), [
        'To do',
        'In progress',
        '',
      ]);
      expect(source.groups.map((group) => group.key), [
        'id:3',
        'id:7',
        'empty',
      ]);
    });

    test('compares the relation to the target id', () async {
      final source = await resolveGroupSource(api, 'status');
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.first.predicate, ['status', '=', 3]);
      expect(source.groups.last.predicate, ['status', 'is empty']);
    });

    test('leaves the ordering to the target default', () async {
      final source = await resolveGroupSource(api, 'status');
      addTearDown(source!.dispose);
      await source.load();

      // flow_status declares default_order_by (sequence, name): forcing an
      // alphabetical order here would put the buckets in the wrong order.
      expect(requests.single.queryParameters.containsKey('order_by'), isFalse);
    });

    test('appends the empty bucket on the last page only', () async {
      statuses = [
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'},
        {'id': 3, 'name': 'C'},
      ];
      statusTotal = 3;

      final source = await resolveGroupSource(api, 'status', limit: 2);
      addTearDown(source!.dispose);
      await source.load();

      expect(source.groups.map((group) => group.label), ['A', 'B']);
      expect(source.total, 4);
      expect(source.hasNextPage, isTrue);

      await source.setPage(2);

      expect(source.groups.map((group) => group.label), ['C', '']);
      expect(source.groups.last.isEmptyBucket, isTrue);
    });

    test('an unreachable target leaves nothing to show', () async {
      final source = await resolveGroupSource(api, 'status');
      addTearDown(source!.dispose);
      statuses = [];
      statusTotal = 0;

      final offline = createMockFetcher(
        (request) => const MockResponse.error(503),
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      );
      // The axis is read through the api's own fetcher, so a source built on a
      // failing one is what an offline launch produces.
      final broken = await resolveGroupSource(
        _FlowApi(fetcher: offline),
        'status',
      );
      addTearDown(broken!.dispose);

      await broken.load();

      // Not "everything has no status": the axis is unknown, so it holds no
      // bucket at all — not even the empty one.
      expect(broken.groups, isEmpty);
      expect(broken.total, 0);
      expect(broken.requiresConnection, isTrue);
    });
  });

  group('groupable fields', () {
    test('a date is not groupable without a server group by', () async {
      expect(await resolveGroupSource(api, 'due_date'), isNull);
    });

    test('a to-many field is not groupable', () async {
      expect(await resolveGroupSource(api, 'assignees'), isNull);
      expect(await resolveGroupSource(api, 'attachments'), isNull);
    });

    test('free text is not groupable', () async {
      expect(await resolveGroupSource(api, 'name'), isNull);
    });

    test('an unknown field is not groupable', () async {
      expect(await resolveGroupSource(api, 'nope'), isNull);
    });
  });
}
