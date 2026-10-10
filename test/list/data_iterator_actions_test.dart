/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/workspace.dart' show WorkspaceSwitchedEvent;
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'list_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ThingApi api;

  setUp(() async {
    await setUpList(sortable: true, sortableField: 'rank');
    server = ThingServer();
    api = ThingApi(server.fetcher);
  });

  List<MockRequest> orders() => [
    for (final request in server.requests)
      if (request.path.endsWith('/dataset/resequence')) request,
  ];

  group('the manual order', () {
    test(
      'sends the rank of the rows it orders, and the group they move to',
      () async {
        final list = DataIterator<Thing>(api);

        await settle();
        list.currentPage = 3;
        await settle();
        await list.resequence([105, 104], groupField: 'status', groupValue: 2);

        expect(orders().single.path, '/acme/dataset/resequence');
        expect(orders().single.body, {
          'model_name': 'thing',
          'sequence_offset': 100,
          'sequence_field': 'rank',
          'group_field': 'status',
          'group_value': 2,
          'ids': [105, 104],
        });
        expect(sent(server.lists.last)['offset'], 100);

        list.dispose();
      },
    );

    test('puts the rows in their new order at once, and counts from the first row when it appends', () async {
      final list = DataIterator<Thing>(api, append: true);
      final answered = Completer<void>();

      await settle();
      await list.loadMore();
      server.answer = (request) async {
        if (request.method != 'PUT') {
          return null;
        }

        await answered.future;

        return const MockResponse.json({});
      };

      final saving = list.resequence([3, 1, 2]);

      await settle();

      expect(list.items.take(3).map((row) => row.id), [3, 1, 2]);
      expect(list.loading, isTrue);

      answered.complete();
      await saving;

      expect((orders().single.body as Map)['sequence_offset'], 0);
      expect(list.loading, isFalse);

      list.dispose();
    });

    test('sends the order where it is told the dataset routes are', () async {
      final list = DataIterator<Thing>(api, datasetPrefix: '');

      await settle();
      await list.resequence([2, 1]);

      expect(orders().single.path, '/dataset/resequence');

      list.dispose();
    });

    test(
      'stops while a search narrows the list, and reads the rows again instead',
      () async {
        final list = DataIterator<Thing>(api);

        await settle();
        expect(list.isSortable, isTrue);

        list.search = 'lamp';
        await Future<void>.delayed(const Duration(milliseconds: 310));
        await settle();

        expect(list.isSortable, isFalse);

        await list.resequence([2, 1]);

        expect(orders(), isEmpty);
        expect(server.lists, hasLength(3));

        list.dispose();
      },
    );

    test('reads the rows again and throws what the server refused', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      server.answer = (request) => request.method == 'PUT'
          ? const MockResponse.error(400, body: {'detail': 'No'})
          : null;

      await expectLater(list.resequence([2, 1]), throwsA(isA<HttpError>()));
      expect(server.lists, hasLength(2));
      expect(list.items.first.id, 1);

      list.dispose();
    });

    test('keeps the order in sequence when it is forced on a model the metadata do not describe', () async {
      final ghost = _GhostApi(server.fetcher);
      final list = DataIterator<Thing>(ghost, sortable: true);

      await settle();

      expect(list.isSortable, isTrue);
      expect(list.fields, ['id', 'sequence']);

      list.dispose();
    });
  });

  group('the selection', () {
    test('keeps every record of the filter but those unchecked, and sends them out', () async {
      final list = DataIterator<Thing>(api, filter: ['kind', '=', 1]);

      await settle();
      list.selection
        ..all = true
        ..remove([3, 4]);

      expect(list.selection.count, 118);
      expect(list.selection.has(3), isFalse);
      expect(list.selection.has(5), isTrue);
      expect(selectionFilter(list), [
        ['kind', '=', 1],
        [
          'id',
          'not in',
          [3, 4],
        ],
      ]);

      list.selection.add([3]);

      expect(list.selection.excluded, [4]);

      list.selection.toggleAll();

      expect(list.selection.count, 0);
      expect(selectionFilter(list), ['id', 'in', []]);

      list.dispose();
    });

    test('keeps the rows chosen from one page to another, and forgets them when the filter changes', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      list.selection.selectAllVisible();

      expect(list.selection.isAllVisibleSelected, isTrue);
      expect(list.selection.shouldShowSelectAllButton, isTrue);

      list.currentPage = 2;
      await settle();

      expect(list.selection.count, 50);

      list.expression = ['name', '=', 'a'];
      await settle();

      expect(list.selection.count, 0);

      list.dispose();
    });
  });

  group('the realtime socket', () {
    void announce(ResourceChangeType type, int id) => getService<Bus>().fire(
      ResourceChangedEvent(null, model: 'thing', type: type, id: id),
    );

    test('reads the rows again once for a burst of changes, and drops a row deleted', () async {
      final list = DataIterator<Thing>(
        api,
        refreshDelay: const Duration(milliseconds: 20),
      );

      await settle();
      announce(ResourceChangeType.updated, 3);
      announce(ResourceChangeType.updated, 4);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await settle();

      expect(server.lists, hasLength(2));

      announce(ResourceChangeType.deleted, 5);
      await settle();

      expect(list.byId(5), isNull);
      expect(list.total, 119);
      expect(server.lists, hasLength(2));

      list.dispose();
    });

    test('keeps the changes for when it is shown again', () async {
      final list = DataIterator<Thing>(
        api,
        refreshDelay: const Duration(milliseconds: 20),
      );

      await settle();
      list.active = false;
      announce(ResourceChangeType.updated, 3);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(server.lists, hasLength(1));

      list.active = true;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await settle();

      expect(server.lists, hasLength(2));

      list.dispose();
    });
  });

  group('a workspace switch', () {
    test('starts the list over: its opening state, the metadata read again, one read', () async {
      final late = QuickFilter<bool>(
        name: 'late',
        defaultValue: false,
        filter: (late) => late == true ? ['late', 'is true'] : null,
      );
      final url = MemoryListUrl(
        initial: {'p': '3', 'q': 'lamp', 'qf': '{"late":true}'},
      );
      final list = DataIterator<Thing>(
        api,
        url: url,
        quickFilters: [late],
        defaultOrderBy: ['id:asc'],
      );

      await settle();
      list
        ..filter = ['owner', '=', 1]
        ..expression = ['name', '=', 'a']
        ..orderBy = ['name:desc'];
      await settle();
      list.selection.add([1]);

      final metadata = getService<MetadataProvider>() as FakeMetadataProvider;

      metadata.models['thing'] = metaModel(
        'thing',
        apiName: 'things',
        fields: {},
      );

      final old = Completer<void>();

      server.gates.add(old);
      unawaited(list.refresh());
      await settle();
      final before = server.lists.length;

      getService<Bus>().fire(const WorkspaceSwitchedEvent());
      await settle();
      old.complete();
      await settle();

      expect(server.lists, hasLength(before + 1));
      expect(sent(server.lists.last), {
        'offset': 0,
        'limit': 50,
        'filter': null,
        'fields': 'id',
        'order': 'id:asc',
      });
      expect(list.currentPage, 1);
      expect(list.search, '');
      expect(list.filter, isNull);
      expect(list.expression, isNull);
      expect(list.quick, {'late': false});
      expect(list.selection.count, 0);
      expect(list.isSortable, isFalse);
      expect(list.items, hasLength(50));
      expect(list.loaded, isTrue);
      expect(url.query, isEmpty);

      list.dispose();
    });
  });

  group('the quick filters', () {
    final closed = QuickFilter<bool>(
      name: 'closed',
      defaultValue: false,
      filter: (shown) => shown == true ? null : ['status', '=', 'open'],
    );

    test('send their rules, read from the url, and keep there those away from their default', () async {
      final url = MemoryListUrl(initial: {'qf': '{"closed":true}'});
      final list = DataIterator<Thing>(api, url: url, quickFilters: [closed]);

      await settle();

      expect(list.quick, {'closed': true});
      expect(sent(server.lists.single)['filter'], isNull);

      list.setQuick('closed', false);
      await settle();

      expect(sent(server.lists.last)['filter'], [
        ['status', '=', 'open'],
      ]);
      expect(url.query, isEmpty);

      list.dispose();
    });

    test('stay at their default when the url does not read', () {
      expect(readQuickFilters('{not', [closed]), {'closed': false});
      expect(readQuickFilters('[1]', [closed]), {'closed': false});
      expect(writeQuickFilters({'closed': false}, [closed]), isNull);
      expect(writeQuickFilters({'closed': true}, [closed]), '{"closed":true}');
    });
  });

  group('export and import', () {
    test('exports every record of the filter, in its order', () async {
      server.answer = (request) => request.path.endsWith('/export')
          ? const MockResponse.json('id,name')
          : null;
      final list = DataIterator<Thing>(
        api,
        fields: ['name'],
        defaultOrderBy: ['name:asc'],
        filter: ['kind', '=', 1],
      );

      await settle();
      final bytes = await list.exportData(format: 'xlsx');
      final request = server.requests.last;

      expect(utf8.decode(bytes), jsonEncode('id,name'));
      expect(request.path, '/acme/things/export');
      expect(request.queryParameters['format'], 'xlsx');
      expect(request.queryParameters['order_by'], 'name:asc');
      expect(request.queryParameters.containsKey('limit'), isFalse);
      expect(request.headers['X-Fields'], 'id,name,rank');
      expect(jsonDecode(request.headers['X-Filter'] as String), [
        'kind',
        '=',
        1,
      ]);

      list.dispose();
    });

    test(
      'sends the separator of a csv, and reads the rows again once one passed',
      () async {
        server.answer = (request) => request.path.endsWith('/import')
            ? const MockResponse.json({'success': 2, 'created': 2})
            : null;
        final list = DataIterator<Thing>(api);

        await settle();
        final result = await list.importData(
          [1, 2],
          'things.csv',
          delimiter: ';',
        );
        final form =
            server.requests.firstWhere((one) => one.method == 'POST').body
                as FormData;

        expect(result.created, 2);
        expect(form.fields.map((field) => (field.key, field.value)), [
          ('delimiter', ';'),
        ]);
        expect(server.lists, hasLength(2));

        list.dispose();
      },
    );

    test('gives the rows refused as a result, not as a failure', () async {
      server.answer = (request) => request.path.endsWith('/import')
          ? const MockResponse.error(
              400,
              body: {
                'detail': {
                  'message': 'Import failed: 1 error(s) found',
                  'success': 0,
                  'errors': 1,
                  'created': 0,
                  'updated': 0,
                  'error_details': [
                    {
                      'row': 2,
                      'error': 'Name is required',
                      'data': {'name': ''},
                    },
                  ],
                },
              },
            )
          : null;
      final list = DataIterator<Thing>(api);

      await settle();
      final result = await list.importData([1], 'things.csv');

      expect(result.errors, 1);
      expect(result.errorDetails.single.row, 2);
      expect(result.errorDetails.single.error, 'Name is required');
      expect(server.lists, hasLength(1));

      list.dispose();
    });
  });

  group('the scroll', () {
    testWidgets(
      'restores the position of the url and keeps the new one there',
      (tester) async {
        final controller = ScrollController();
        final url = MemoryListUrl(initial: {'sl': '300'});
        late DataIterator<Thing> list;

        await tester.runAsync(() async {
          list = DataIterator<Thing>(
            api,
            append: true,
            scrollController: controller,
            url: url,
          );
          await settle();
        });

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ListenableBuilder(
              listenable: list,
              builder: (context, _) => ListView(
                controller: controller,
                children: [
                  for (final row in list.items)
                    SizedBox(height: 40, child: Text('${row.id}')),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(controller.offset, 300);

        controller.jumpTo(120);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(settle);

        expect(url.query['sl'], '120');

        list.dispose();
      },
    );
  });
}

/// A model the metadata do not describe.
class _GhostApi extends ApiModel<Thing> {
  _GhostApi(Fetcher fetcher)
    : super('/acme', modelName: 'ghost', fetcher: fetcher);

  @override
  Thing fromJson(Map<String, dynamic> json) => Thing(json);
}
