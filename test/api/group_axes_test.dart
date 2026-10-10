/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

class _Flow extends BaseModel<_Flow> {
  _Flow(super.data);
}

class _FlowApi extends ApiModel<_Flow> {
  _FlowApi(Fetcher fetcher)
    : super('/{workspace}', modelName: 'flow', fetcher: fetcher);

  @override
  _Flow fromJson(Map<String, dynamic> json) => _Flow(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late _FlowApi api;

  setUp(() async {
    await container.reset(dispose: false);
    container
      ..registerSingleton<Bus>(Bus())
      ..registerSingleton<MetadataProvider>(fakeMetadataProvider());
    requests = [];
    api = _FlowApi(
      createMockFetcher(
        (request) {
          requests.add(request);

          final items = request.path.endsWith('/flow_statuses')
              ? [
                  {
                    'id': 3,
                    'name': 'To do',
                    'color': '#ff0000',
                    'is_done': false,
                  },
                  {'id': 7, 'name': 'Done', 'color': null, 'is_done': true},
                ]
              : [
                  {'id': 1, 'name': 'A'},
                ];

          return MockResponse.json({
            'items': items,
            'total': items.length,
            'limit': 50,
            'offset': 0,
            'total_pages': 1,
          });
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  Object? filterOf(MockRequest request) {
    final raw = request.headers['X-Filter'] as String?;

    return raw == null ? null : jsonDecode(raw);
  }

  test(
    'groups a boolean by yes and no, with no request and no empty bucket',
    () async {
      final source = await resolveGroupSource(
        api,
        'urgent',
        yesLabel: 'Oui',
        noLabel: 'Non',
      );

      await source!.load();

      expect(source.groups.map((group) => (group.label, group.value)), [
        ('Oui', true),
        ('Non', false),
      ]);
      expect(source.groups.first.predicate, ['urgent', 'is true']);
      expect(requests, isEmpty);
    },
  );

  test('puts the empty bucket first when asked, and colors the choices the caller colors', () async {
    final source = await resolveGroupSource(
      api,
      'priority',
      emptyFirst: true,
      colorOf: (value) => value == 'high' ? 'red' : null,
    );

    await source!.load();

    expect(source.groups.first.isEmptyBucket, isTrue);
    expect(source.groups.map((group) => group.color), [
      null,
      null,
      null,
      'red',
      null,
    ]);
  });

  test('reads the records of a relation with their color, the fields asked and the scope', () async {
    final source = await resolveGroupSource(
      api,
      'status',
      fields: ['is_done'],
      filter: ['is_done', 'is false'],
      emptyFirst: true,
    );

    await source!.load();

    expect(requests.single.headers['X-Fields'], 'id,name,color,is_done');
    expect(filterOf(requests.single), ['is_done', 'is false']);
    expect(source.groups.map((group) => group.key), ['empty', 'id:3', 'id:7']);
    expect(source.groups[1].color, '#ff0000');
    expect(source.groups[2].record?['is_done'], isTrue);

    source.dispose();
  });

  test('adds the rule of one bucket to its read alone, and puts the buckets in another order', () async {
    final source = await resolveGroupSource(api, 'status');
    final grouped = GroupedApiCollection<_Flow>(
      api,
      source!,
      filter: ['name', 'icontains', 'a'],
      groupFilter: (group) => group.record?['is_done'] == true
          ? ['closed_at', '>=', '2026-10-05']
          : null,
    );

    await grouped.load();

    final reads = {
      for (final request in requests.skip(1)) jsonEncode(filterOf(request)),
    };

    expect(reads, {
      jsonEncode([
        '&',
        [
          ['name', 'icontains', 'a'],
          ['status', '=', 3],
        ],
      ]),
      jsonEncode([
        '&',
        [
          ['name', 'icontains', 'a'],
          ['status', '=', 7],
          ['closed_at', '>=', '2026-10-05'],
        ],
      ]),
      jsonEncode([
        '&',
        [
          ['name', 'icontains', 'a'],
          ['status', 'is empty'],
        ],
      ]),
    });

    grouped.reorderGroups(['id:7']);

    expect(grouped.entries.map((entry) => entry.group.key), [
      'id:7',
      'id:3',
      'empty',
    ]);

    final before = requests.length;

    await grouped.refresh();

    expect(requests.length, before + 3);

    grouped.dispose();
  });
}
