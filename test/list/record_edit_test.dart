/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'list_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ThingApi api;
  late List<Map<String, dynamic>> things;
  late List<Completer<void>> holds;
  MockResponse? refusal;

  List<MockRequest> writes() => [
    for (final request in server.requests)
      if (request.method != 'GET') request,
  ];

  int reads() => server.lists.length;

  setUp(() async {
    final metadata = await setUpList(
      fields: {
        'stage': metaField('stage', type: 'many2one', target: 'stage'),
        'tags': metaField('tags', type: 'many2many', target: 'tag'),
        'due': metaField('due', type: 'date'),
        'at': metaField('at', type: 'datetime'),
      },
    );

    metadata.models['stage'] = metaModel(
      'stage',
      apiName: 'stages',
      fields: {
        'id': metaField('id', type: 'integer'),
        'name': metaField('name', type: 'char'),
      },
    );
    things = [
      {
        'id': 1,
        'name': 'Lamp',
        'stage': {'id': 1, 'name': 'To do'},
      },
      {
        'id': 2,
        'name': 'Desk',
        'stage': {'id': 2, 'name': 'Done'},
      },
    ];
    holds = [];
    refusal = null;
    server = ThingServer();
    server.answer = (request) async {
      final rows = switch (request.path) {
        '/acme/stages' => [
          {'id': 1, 'name': 'To do'},
          {'id': 2, 'name': 'Done'},
        ],
        '/acme/things' => things,
        _ => null,
      };

      if (request.method == 'GET' && rows != null) {
        final filter = sent(request)['filter'];
        final stage = filter is List && filter.length == 3 ? filter[2] : null;
        final items = [
          for (final row in rows)
            if (stage == null || (row['stage'] as Map?)?['id'] == stage) row,
        ];

        return MockResponse.json({
          'items': items,
          'total': items.length,
          'limit': 50,
          'offset': 0,
          'total_pages': 1,
        });
      }

      if (holds.isNotEmpty) {
        await holds.removeAt(0).future;
      }

      final refused = refusal;

      if (refused != null) {
        refusal = null;

        return refused;
      }

      final body = request.body! as Map<String, dynamic>;

      if (request.method == 'POST') {
        return MockResponse.json({'id': 100, ...body});
      }

      final id = int.parse(request.path.split('/').last);
      final row = things.firstWhere((one) => one['id'] == id);

      row.addAll({
        ...body,
        if (body['stage'] case final int stage)
          'stage': {'id': stage, 'name': stage == 1 ? 'To do' : 'Done'},
      });

      return MockResponse.json(row);
    };
    api = ThingApi(server.fetcher);
  });

  test('shows a value at once, writes the id of a relation, and takes the row answered', () async {
    final list = DataIterator<Thing>(api, fields: ['name', 'stage']);
    final cells = RecordEdit<Thing>(list);

    await settle();

    final hold = Completer<void>();

    holds.add(hold);

    final editing = cells.edit(
      list.byId(1)!,
      'stage',
      GenericBaseModel({'id': 2, 'name': 'Done'}),
    );

    await settle();

    expect(list.byId(1)?.data['stage'], {'id': 2, 'name': 'Done'});
    expect(cells.isSaving(list.byId(1), 'stage'), isTrue);

    hold.complete();

    final saved = await editing;

    expect(writes().single.method, 'PATCH');
    expect(writes().single.body, {'stage': 2});
    expect(writes().single.headers['X-Fields'], 'id,name,stage');
    expect(identical(list.byId(1), saved), isTrue);
    expect(cells.isSaving(list.byId(1), 'stage'), isFalse);

    list.dispose();
    cells.dispose();
  });

  test(
    'writes the ids of several records, a day as it is, an instant in UTC',
    () async {
      final list = DataIterator<Thing>(api, fields: ['name']);
      final cells = RecordEdit<Thing>(list);

      await settle();
      await cells.edit(list.byId(1)!, 'tags', [
        GenericBaseModel({'id': 3, 'name': 'Red'}),
        {'id': 4, 'name': 'Blue'},
      ]);
      await cells.edit(list.byId(1)!, 'due', DateTime(2026, 10, 10));
      await cells.edit(list.byId(1)!, 'at', DateTime.utc(2026, 10, 10, 8, 30));

      expect(
        [for (final write in writes()) write.body],
        [
          {
            'tags': [3, 4],
          },
          {'due': '2026-10-10'},
          {'at': '2026-10-10T08:30:00.000Z'},
        ],
      );

      list.dispose();
      cells.dispose();
    },
  );

  test('puts the value back on a refusal, its message kept on its cell or on its row', () async {
    final errors = <Object>[];
    final list = DataIterator<Thing>(api, fields: ['name']);
    final cells = RecordEdit<Thing>(list, onError: errors.add);

    await settle();

    refusal = const MockResponse.error(
      422,
      body: {
        'detail': [
          {
            'loc': ['body', 'name'],
            'msg': 'Too short',
            'type': 'value_error',
          },
        ],
      },
    );

    expect(await cells.edit(list.byId(1)!, 'name', 'L'), isNull);
    expect(list.byId(1)?.data['name'], 'Lamp');
    expect(cells.errorOf(list.byId(1), 'name'), 'Too short');
    expect(cells.rowErrorOf(list.byId(1)), isNull);
    expect(errors, hasLength(1));

    refusal = const MockResponse.error(400, body: {'detail': 'Locked'});

    await cells.edit(list.byId(1)!, 'name', 'Lantern');

    expect(cells.rowErrorOf(list.byId(1)), 'Locked');
    expect(cells.errorOf(list.byId(1), 'name'), isNull);

    await cells.edit(list.byId(1)!, 'name', 'Lantern');

    expect(list.byId(1)?.data['name'], 'Lantern');
    expect(cells.rowErrorOf(list.byId(1)), isNull);

    list.dispose();
    cells.dispose();
  });

  test(
    'writes nothing for a value the row holds, and reads no echo of its writes',
    () async {
      final list = DataIterator<Thing>(
        api,
        fields: ['name'],
        refreshDelay: Duration.zero,
      );
      final cells = RecordEdit<Thing>(list);

      await settle();
      await cells.edit(list.byId(1)!, 'name', 'Lamp');

      expect(writes(), isEmpty);

      final read = reads();

      await cells.edit(list.byId(1)!, 'name', 'Lantern');
      await settle();

      expect(writes(), hasLength(1));
      expect(reads(), read);

      list.dispose();
      cells.dispose();
    },
  );

  test('moves a row to the group of its new value at once', () async {
    final list = DataIterator<Thing>(api, groupBy: 'stage', fields: ['name']);
    final cells = RecordEdit<Thing>(list);

    await settle();

    final editing = cells.edit(list.byId(1)!, 'stage', {
      'id': 2,
      'name': 'Done',
    });

    await settle();

    expect([for (final row in list.groups[1].items) row.id], [2, 1]);
    expect(list.groups.first.items, isEmpty);

    await editing;

    list.dispose();
    cells.dispose();
  });

  test('writes through the write of the app', () async {
    final calls = <(Object?, String, Object?)>[];
    final list = DataIterator<Thing>(api, fields: ['name']);
    final cells = RecordEdit<Thing>(
      list,
      write: (item, field, value) async {
        calls.add((item.id, field, value));

        return null;
      },
    );

    await settle();
    await cells.edit(list.byId(2)!, 'stage', {'id': 1, 'name': 'To do'});

    expect(calls, [(2, 'stage', 1)]);
    expect(writes(), isEmpty);
    expect(list.byId(2)?.data['stage'], {'id': 1, 'name': 'To do'});

    list.dispose();
    cells.dispose();
  });

  test('creates the record of the draft at the start of the list, or keeps the messages on the draft', () async {
    final list = DataIterator<Thing>(api, fields: ['name']);
    final cells = RecordEdit<Thing>(list);

    await settle();

    refusal = MockResponse.error(
      422,
      body: jsonDecode(
        '{"detail": [{"loc": ["body", "name"], "msg": "Required", "type": "missing"}]}',
      ),
    );

    expect(
      await cells.create({
        'stage': GenericBaseModel({'id': 1}),
      }),
      isNull,
    );
    expect(cells.errorOf(null, 'name'), 'Required');

    final hold = Completer<void>();

    holds.add(hold);

    final creating = cells.create({
      'name': 'Chair',
      'stage': {'id': 1},
    });

    await settle();

    expect(cells.isSaving(null, 'name'), isTrue);

    hold.complete();

    final created = await creating;

    expect(writes().last.body, {'name': 'Chair', 'stage': 1});
    expect(list.items.first.id, created?.id);
    expect(list.total, 3);
    expect(cells.errorOf(null, 'name'), isNull);

    list.dispose();
    cells.dispose();
  });
}
