/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart' show WorkspaceSwitchedEvent;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'list_support.dart';

Object? _value(Object? raw) => raw is Map ? raw['id'] : raw;

/// Whether [row] holds under [filter]: a rule, a group of them, or a list of
/// them all applying.
bool _matches(Map<String, dynamic> row, Object? filter) {
  if (filter is! List || filter.isEmpty) {
    return true;
  }

  final head = filter.first;

  if (head == '&' || head == '|') {
    final items = filter[1] as List;

    return head == '&'
        ? items.every((item) => _matches(row, item))
        : items.any((item) => _matches(row, item));
  }

  if (head is List) {
    return filter.every((item) => _matches(row, item));
  }

  final value = _value(row[head]);
  final operand = filter.length > 2 ? filter[2] : null;

  return switch (filter[1]) {
    '=' => value == operand,
    '!=' => value != operand,
    'is empty' => value == null,
    'is true' => value == true,
    'is false' => value == false,
    'in' => (operand as List).contains(value),
    'not in' => !(operand as List).contains(value),
    'icontains' => '$value'.toLowerCase().contains('$operand'.toLowerCase()),
    _ => throw UnsupportedError('${filter[1]}'),
  };
}

/// Things with a stage, a priority, a flag and a size of the workspace, read
/// by their filter in their manual order, moved, resequenced and written.
class GroupServer {
  GroupServer(this.server) : _before = server.answer {
    server.answer = _answer;
  }

  final ThingServer server;

  /// What answered before, the custom views for one.
  final FutureOr<MockResponse?> Function(MockRequest request)? _before;

  final things = <Map<String, dynamic>>[
    {
      'id': 1,
      'name': 'Lamp',
      'stage': 1,
      'priority': 'low',
      'urgent': true,
      'extra_size': 's',
      'sequence': 1,
    },
    {
      'id': 2,
      'name': 'Desk',
      'stage': 1,
      'priority': 'high',
      'urgent': false,
      'extra_size': 'l',
      'sequence': 2,
    },
    {
      'id': 3,
      'name': 'Chair',
      'stage': 2,
      'priority': 'high',
      'urgent': false,
      'extra_size': null,
      'sequence': 3,
    },
    {
      'id': 4,
      'name': 'Shelf',
      'stage': null,
      'priority': null,
      'urgent': false,
      'extra_size': null,
      'sequence': 4,
    },
    {
      'id': 5,
      'name': 'Table',
      'stage': 2,
      'priority': 'low',
      'urgent': true,
      'extra_size': 's',
      'sequence': 5,
    },
  ];

  final stages = <Map<String, dynamic>>[
    {
      'id': 1,
      'name': 'To do',
      'color': '#ff0000',
      'is_done': false,
      'sequence': 1,
    },
    {'id': 2, 'name': 'Done', 'color': null, 'is_done': true, 'sequence': 2},
  ];

  /// Holds back the next writes, in turn.
  final holds = <Completer<void>>[];

  /// Refuses the next writes.
  var refuse = false;

  List<MockRequest> reads(String path) => [
    for (final request in server.requests)
      if (request.method == 'GET' && request.path == path) request,
  ];

  List<MockRequest> get writes => [
    for (final request in server.requests)
      if (request.method != 'GET') request,
  ];

  /// The filter of each read of the things.
  List<Object?> get filters => [
    for (final request in reads('/acme/things')) sent(request)['filter'],
  ];

  Future<MockResponse?> _answer(MockRequest request) async {
    if (request.method == 'GET') {
      final rows = switch (request.path) {
        '/acme/things' => things,
        '/acme/stages' => stages,
        _ => null,
      };

      return rows == null ? _before?.call(request) : _list(request, rows);
    }

    if (!request.path.endsWith('/dataset/resequence') &&
        !request.path.startsWith('/acme/things/')) {
      return _before?.call(request);
    }

    if (holds.isNotEmpty) {
      await holds.removeAt(0).future;
    }

    if (refuse) {
      return const MockResponse.error(400, body: {'detail': 'Refused'});
    }

    final body = request.body is String
        ? jsonDecode(request.body! as String) as Map<String, dynamic>
        : request.body! as Map<String, dynamic>;

    if (request.path.endsWith('/dataset/resequence')) {
      final rows = body['model_name'] == 'stage' ? stages : things;
      final ids = body['ids'] as List;

      for (final (index, id) in ids.indexed) {
        final row = rows.firstWhere((one) => one['id'] == id);

        row[body['sequence_field'] as String] =
            (body['sequence_offset'] as int) + index;

        if (body['group_field'] case final String field) {
          row[field] = body['group_value'];
        }
      }

      return MockResponse.json({...body, 'records': const []});
    }

    final id = int.parse(request.path.split('/').last);
    final row = things.firstWhere((one) => one['id'] == id)..addAll(body);

    return MockResponse.json(row);
  }

  MockResponse _list(MockRequest request, List<Map<String, dynamic>> rows) {
    final filter = sent(request)['filter'];
    final limit = request.queryParameters['limit'] as int? ?? 50;
    final offset = request.queryParameters['offset'] as int? ?? 0;
    final matched = [
      for (final row in rows)
        if (_matches(row, filter)) row,
    ]..sort((a, b) => (a['sequence']! as int).compareTo(b['sequence']! as int));

    return MockResponse.json({
      'items': [
        for (final row in matched.skip(offset).take(limit)) {...row},
      ],
      'total': matched.length,
      'limit': limit,
      'offset': offset,
      'total_pages': (matched.length / limit).ceil(),
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late GroupServer groups;
  late ThingApi api;

  setUp(() async {
    final metadata = await setUpList(
      sortable: true,
      fields: {
        'stage': metaField('stage', type: 'many2one', target: 'stage'),
        'priority': metaField(
          'priority',
          type: 'choice',
          choices: {'low': 'Low', 'high': 'High'},
        ),
        'level': metaField(
          'level',
          type: 'choice',
          required: true,
          choices: {'one': 'One'},
        ),
        'kind': metaField(
          'kind',
          type: 'choice',
          readonly: true,
          choices: {'a': 'A'},
        ),
        'urgent': metaField('urgent', type: 'boolean'),
        'extra_size': metaField(
          'extra_size',
          type: 'choice',
          extra: true,
          choices: {'s': 'S', 'l': 'L'},
        ),
        'sequence': metaField('sequence', type: 'integer'),
      },
    );

    metadata.models['stage'] = metaModel(
      'stage',
      apiName: 'stages',
      sortable: true,
      fields: {
        'id': metaField('id', type: 'integer'),
        'name': metaField('name', type: 'char'),
        'color': metaField('color', type: 'char'),
        'is_done': metaField('is_done', type: 'boolean'),
        'sequence': metaField('sequence', type: 'integer'),
      },
    );
    server = ThingServer();
    groups = GroupServer(server);
    api = ThingApi(server.fetcher);
  });

  List<String> labels(DataIterator<Thing> list) => [
    for (final group in list.groups) group.label,
  ];

  List<Object?> idsOf(DataGroup<Thing> group) => [
    for (final row in group.items) row.id,
  ];

  DataGroup<Thing> groupOf(DataIterator<Thing> list, String key) =>
      list.groups.firstWhere((group) => group.key == key);

  group('the axis', () {
    test('groups by the choices of a field, each read with the filter of the list and its predicate, the axis read by none', () async {
      final list = DataIterator<Thing>(
        api,
        groupBy: 'priority',
        fields: ['name'],
      );

      await settle();

      expect(labels(list), ['Low', 'High', 'No value']);
      expect(groups.filters, [
        ['priority', '=', 'low'],
        ['priority', '=', 'high'],
        ['priority', 'is empty'],
      ]);
      expect(list.total, 5);
      expect(list.items, hasLength(5));
      expect(list.loaded, isTrue);

      list.filter = ['name', 'icontains', 'a'];
      await settle();

      expect(groups.filters.skip(3), [
        for (final predicate in [
          ['priority', '=', 'low'],
          ['priority', '=', 'high'],
          ['priority', 'is empty'],
        ])
          [
            '&',
            [
              [
                ['name', 'icontains', 'a'],
              ],
              predicate,
            ],
          ],
      ]);
      expect([for (final group in list.groups) group.total], [2, 1, 0]);
      expect(list.total, 3);

      list.dispose();
    });

    test('groups by a boolean, yes then no', () async {
      final list = DataIterator<Thing>(api, groupBy: 'urgent');

      await settle();

      expect(labels(list), ['Yes', 'No']);
      expect(groups.filters, [
        ['urgent', 'is true'],
        ['urgent', 'is false'],
      ]);
      expect(groups.reads('/acme/stages'), isEmpty);

      list.dispose();
    });

    test('groups by the records of a relation, in the scope of the relation, with their color and the fields asked', () async {
      final list = DataIterator<Thing>(
        api,
        groupBy: 'stage',
        groupFields: ['is_done'],
        relationScopes: {
          'stage': ['is_done', 'is false'],
        },
      );

      await settle();

      final axis = sent(groups.reads('/acme/stages').single);

      expect(axis['fields'], 'id,name,color,is_done');
      expect(axis['filter'], ['is_done', 'is false']);
      expect(axis['limit'], 50);
      expect(labels(list), ['To do', 'No value']);
      expect(list.groups.first.color, '#ff0000');
      expect(list.groups.first.record?['is_done'], isFalse);
      expect(list.groupPage, 1);
      expect(list.groupTotalPages, 1);

      list.dispose();
    });

    test('puts the group with no value first, or leaves it out, and has none for a required field', () async {
      final first = DataIterator<Thing>(
        api,
        groupBy: 'priority',
        emptyGroup: EmptyGroup.first,
      );
      final none = DataIterator<Thing>(
        api,
        groupBy: 'priority',
        emptyGroup: EmptyGroup.none,
      );
      final required = DataIterator<Thing>(api, groupBy: 'level');

      await settle();

      expect(labels(first), ['No value', 'Low', 'High']);
      expect(labels(none), ['Low', 'High']);
      expect(labels(required), ['One']);

      for (final list in [first, none, required]) {
        list.dispose();
      }
    });

    test('says a field that does not group, and reads nothing', () async {
      final list = DataIterator<Thing>(api, groupBy: 'name');

      await settle();

      expect(list.error, "This field can't be grouped.");
      expect(list.availability, DataAvailability.failed);
      expect(list.groups, isEmpty);
      expect(groups.reads('/acme/things'), isEmpty);
      expect(list.loaded, isTrue);
      expect(
        [for (final field in list.groupableFields) field.name],
        ['stage', 'priority', 'level', 'kind', 'urgent', 'extra_size'],
      );

      list.dispose();
    });

    test(
      'adds the rule of the list to the read of the group it is for alone',
      () async {
        final list = DataIterator<Thing>(
          api,
          groupBy: 'stage',
          groupFilter: (group) => group.record?['is_done'] == true
              ? ['name', 'icontains', 'e']
              : null,
        );

        await settle();

        expect(groups.filters, [
          ['stage', '=', 1],
          [
            '&',
            [
              ['stage', '=', 2],
              ['name', 'icontains', 'e'],
            ],
          ],
          ['stage', 'is empty'],
        ]);
        expect(groupOf(list, 'id:2').filter, [
          '&',
          [
            ['stage', '=', 2],
            ['name', 'icontains', 'e'],
          ],
        ]);

        list.dispose();
      },
    );
  });

  group('the rows of a group', () {
    test('page, or follow one another', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage', rowLimit: 1);

      await settle();

      final todo = groupOf(list, 'id:1');

      expect(idsOf(todo), [1]);
      expect(todo.hasMore, isTrue);
      expect(todo.totalPages, 2);

      await todo.setPage(2);

      expect(idsOf(groupOf(list, 'id:1')), [2]);
      expect(sent(groups.reads('/acme/things').last)['offset'], 1);

      await groupOf(list, 'id:1').setPage(1);
      await groupOf(list, 'id:1').loadMore();

      expect(idsOf(groupOf(list, 'id:1')), [1, 2]);
      expect(list.hasMore, isFalse);

      list.dispose();
    });

    test('are read again on the echo of a move once it is done, and not while it runs', () async {
      final list = DataIterator<Thing>(
        api,
        groupBy: 'stage',
        refreshDelay: Duration.zero,
      );

      await settle();

      final hold = Completer<void>();
      final reads = groups.reads('/acme/things').length;
      final echo = ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 1,
        announced: true,
        origin: originId,
      );

      groups.holds.add(hold);

      final moving = list.moveTo(list.byId(1)!, groupOf(list, 'id:2'));

      await settle();
      getService<Bus>().fire(echo);
      await settle();

      expect(groups.reads('/acme/things'), hasLength(reads));

      hold.complete();
      await moving;
      getService<Bus>().fire(echo);
      await settle();

      expect(groups.reads('/acme/things'), hasLength(reads + 3));

      list.dispose();
    });

    test('go to the group of their new value when they change', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage');

      await settle();

      list.upsertLocal(
        Thing({
          'id': 1,
          'name': 'Lamp',
          'stage': {'id': 2},
        }),
      );

      expect(idsOf(groupOf(list, 'id:1')), [2]);
      expect(idsOf(groupOf(list, 'id:2')), [3, 5, 1]);
      expect(groupOf(list, 'id:1').total, 1);

      list.upsertLocal(Thing({'id': 2, 'name': 'Desk again'}));

      expect(list.byId(2)?.data['name'], 'Desk again');
      expect(idsOf(groupOf(list, 'id:1')), [2]);

      list.dispose();
    });
  });

  group('moving', () {
    test('puts a row in another group at once, then sends the order of the group with its value in one request', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage');

      await settle();

      final hold = Completer<void>();

      groups.holds.add(hold);

      final moving = list.moveTo(list.byId(1)!, groupOf(list, 'id:2'), 0);

      expect(idsOf(groupOf(list, 'id:1')), [2]);
      expect(idsOf(groupOf(list, 'id:2')), [1, 3, 5]);
      expect(groupOf(list, 'id:1').total, 1);
      expect(groupOf(list, 'id:2').total, 3);
      expect(list.byId(1)?.data['stage'], containsPair('name', 'Done'));

      hold.complete();
      await moving;

      final write = groups.writes.single;

      expect(write.path, '/acme/dataset/resequence');
      expect(write.body, {
        'model_name': 'thing',
        'ids': [1, 3, 5],
        'sequence_field': 'sequence',
        'sequence_offset': 0,
        'group_field': 'stage',
        'group_value': 2,
      });

      list.dispose();
    });

    test('reads the groups again on a refusal, and throws it', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage');

      await settle();

      groups.refuse = true;

      await expectLater(
        list.moveTo(list.byId(1)!, groupOf(list, 'id:2')),
        throwsA(anything),
      );
      await settle();

      expect(idsOf(groupOf(list, 'id:1')), [1, 2]);
      expect(idsOf(groupOf(list, 'id:2')), [3, 5]);

      list.dispose();
    });

    test('orders a group with no group sent', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage');

      await settle();
      await list.moveTo(list.byId(5)!, groupOf(list, 'id:2'), 0);

      expect(idsOf(groupOf(list, 'id:2')), [5, 3]);
      expect(groups.writes.single.body, {
        'model_name': 'thing',
        'ids': [5, 3],
        'sequence_field': 'sequence',
        'sequence_offset': 0,
      });

      list.dispose();
    });

    test(
      'writes a field of the workspace on the row, then the order without it',
      () async {
        final list = DataIterator<Thing>(api, groupBy: 'extra_size');

        await settle();
        await list.moveTo(list.byId(1)!, groupOf(list, 'value:l'));

        expect(
          [for (final write in groups.writes) write.body],
          [
            {'extra_size': 'l'},
            {
              'model_name': 'thing',
              'ids': [2, 1],
              'sequence_field': 'sequence',
              'sequence_offset': 0,
            },
          ],
        );

        list.dispose();
      },
    );

    test('writes the value alone without a manual order, and moves nothing on a read-only field', () async {
      final list = DataIterator<Thing>(
        api,
        groupBy: 'priority',
        sortable: false,
      );

      await settle();
      await list.moveTo(list.byId(1)!, groupOf(list, 'value:high'));

      expect(groups.writes.single.body, {'priority': 'high'});
      expect(idsOf(groupOf(list, 'value:high')), [2, 3, 1]);

      list.groupBy = 'kind';
      await settle();

      expect(list.canMoveToGroup, isFalse);
      expect(
        () => list.moveTo(list.byId(4)!, groupOf(list, 'value:a')),
        throwsStateError,
      );

      list.dispose();
    });

    test('puts a group of records ordered by hand in its place at once, and back on a refusal', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage');

      await settle();

      expect(list.canMoveGroups, isTrue);

      final hold = Completer<void>();

      groups.holds.add(hold);

      final moving = list.moveGroup(groupOf(list, 'id:2'), 0);

      expect(labels(list), ['Done', 'To do', 'No value']);

      hold.complete();
      await moving;

      expect(groups.writes.single.body, {
        'model_name': 'stage',
        'ids': [2, 1],
        'sequence_field': 'sequence',
        'sequence_offset': 0,
      });

      groups.refuse = true;

      await expectLater(
        list.moveGroup(groupOf(list, 'id:1'), 0),
        throwsA(anything),
      );
      await settle();

      expect(labels(list), ['Done', 'To do', 'No value']);

      list.groupBy = 'priority';
      await settle();

      expect(list.canMoveGroups, isFalse);

      list.dispose();
    });
  });

  group('the state', () {
    test('keeps the grouping in the url after its prefix, none written for the default one', () async {
      final url = MemoryListUrl(prefix: 'tasks_');
      final list = DataIterator<Thing>(api, groupBy: 'stage', url: url);

      await settle();

      expect(url.query, isEmpty);

      list.groupBy = 'priority';
      await settle();

      expect(url.query, {'tasks_g': 'priority'});

      list.groupBy = null;
      await settle();

      expect(url.query, {'tasks_g': 'none'});
      expect(list.items, hasLength(5));
      expect(list.groups, isEmpty);

      url.go({'tasks_g': 'urgent'});
      await settle();

      expect(list.groupBy, 'urgent');
      expect(labels(list), ['Yes', 'No']);

      final opened = DataIterator<Thing>(
        api,
        groupBy: 'stage',
        url: MemoryListUrl(initial: {'g': 'none'}),
      );

      await settle();

      expect(opened.groupBy, isNull);

      list.dispose();
      opened.dispose();
    });

    test('opens on the grouping of its view, saves it, applies it and tells it changed', () async {
      final views = ViewServer(server)
        ..add({'name': 'Urgent', 'is_default': true, 'group_by': 'urgent'});

      GroupServer(server);

      final list = DataIterator<Thing>(
        api,
        groupBy: 'stage',
        views: const DataIteratorViews(),
      );

      await settle();

      expect(list.groupBy, 'urgent');
      expect(labels(list), ['Yes', 'No']);

      final custom = CustomViews('thing', list: list);

      await custom.ensure();

      expect(custom.modified, isFalse);

      list.groupBy = null;

      expect(custom.modified, isTrue);

      await custom.create(name: 'Flat');

      expect(views.views.last['group_by'], 'none');

      custom.apply(custom.items.first);

      expect(list.groupBy, 'urgent');

      list.dispose();
      custom.dispose();
    });

    test('chooses every row of the groups shown, and opens a record in the filter of its group', () async {
      final list = DataIterator<Thing>(
        api,
        groupBy: 'priority',
        emptyGroup: EmptyGroup.none,
        enableSelection: true,
      );

      await settle();

      list.selection.toggleAll();

      expect(selectionFilter(list), [
        '|',
        [
          ['priority', '=', 'low'],
          ['priority', '=', 'high'],
        ],
      ]);
      expect(list.selection.count, 4);
      expect(jsonDecode(listContext(list, group: list.groups.last)['ctx']!), {
        'f': ['priority', '=', 'high'],
      });

      list.dispose();
    });

    test('starts over on its default grouping in another workspace', () async {
      final list = DataIterator<Thing>(api, groupBy: 'stage');

      await settle();

      list.groupBy = 'priority';
      await settle();

      final reads = groups.reads('/acme/stages').length;

      getService<Bus>().fire(const WorkspaceSwitchedEvent());
      await settle();

      expect(list.groupBy, 'stage');
      expect(labels(list), ['To do', 'Done', 'No value']);
      expect(groups.reads('/acme/stages'), hasLength(reads + 1));

      list.dispose();
    });
  });
}
