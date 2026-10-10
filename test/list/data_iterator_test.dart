/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'list_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ThingApi api;

  setUp(() async {
    await setUpList();
    server = ThingServer();
    api = ThingApi(server.fetcher);
  });

  group('reading', () {
    test(
      'holds every read back until the caller enables it, then reads once',
      () async {
        final enabled = ValueNotifier(false);
        final list = DataIterator<Thing>(api, enabled: enabled);

        await settle();
        expect(server.lists, isEmpty);

        enabled.value = true;
        await settle();

        expect(server.lists, hasLength(1));
        expect(list.items, hasLength(50));
        expect(list.loaded, isTrue);

        list.dispose();
      },
    );

    test(
      'keeps the latest read when an earlier one answers after it',
      () async {
        final list = DataIterator<Thing>(api);

        await settle();
        final first = Completer<void>();
        final second = Completer<void>();

        server.gates.addAll([first, second]);
        list.search = 'old';
        await Future<void>.delayed(const Duration(milliseconds: 310));
        list.search = 'new';
        await Future<void>.delayed(const Duration(milliseconds: 310));

        second.complete();
        await settle();
        server.rows = 3;
        first.complete();
        await settle();

        expect(list.items, hasLength(50));
        expect(sent(server.lists.last)['filter'], [
          ['search_value', 'search_fuzzy', 'new'],
        ]);

        list.dispose();
      },
    );

    test('reads the id, the fields of the screen and the field of the manual order, once each', () async {
      await setUpList(sortable: true, sortableField: 'rank');
      final list = DataIterator<Thing>(api, fields: ['name', 'id', 'rank']);

      await settle();

      expect(sent(server.lists.single)['fields'], 'id,name,rank');

      list.dispose();
    });

    test('reads again for a field it has not read, not for the fields it just read', () async {
      var fields = ['name'];
      final list = _Fields(api, () => fields);

      await settle();
      list.touch();
      await settle();
      expect(server.lists, hasLength(1));

      fields = ['name', 'code'];
      list.touch();
      await settle();

      expect(server.lists, hasLength(2));
      expect(sent(server.lists.last)['fields'], 'id,name,code');

      list.dispose();
    });

    test('keeps its rows and says why the read failed', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      server.answer = (request) => request.method == 'GET'
          ? const MockResponse.error(500, body: {'detail': 'Down'})
          : null;
      await list.refresh();

      expect(list.error, isNotNull);
      expect(list.items, hasLength(50));
      expect(list.loaded, isTrue);

      list.dispose();
    });
  });

  group('the filter sent', () {
    Future<Object?> filterOf(
      DataIterator<Thing> Function() make, [
      FutureOr<void> Function(DataIterator<Thing> list)? change,
    ]) async {
      final list = make();

      await settle();
      await change?.call(list);
      await Future<void>.delayed(const Duration(milliseconds: 310));
      await settle();
      list.dispose();

      return sent(server.lists.last)['filter'];
    }

    test('is the filter of the screen alone, or nothing', () async {
      expect(await filterOf(() => DataIterator<Thing>(api)), isNull);
      expect(
        await filterOf(
          () => DataIterator<Thing>(api, filter: ['name', '=', 'a']),
        ),
        ['name', '=', 'a'],
      );
    });

    test('adds the filter of the controls, the expression, the quick filters and the search, in this order', () async {
      final late = QuickFilter<bool>(
        name: 'late',
        defaultValue: false,
        filter: (late) => late == true ? ['late', 'is true'] : null,
      );

      expect(
        await filterOf(
          () => DataIterator<Thing>(
            api,
            filter: [
              ['kind', '=', 1],
            ],
            quickFilters: [late],
            searchFields: ['name', 'code'],
          ),
          (list) {
            list
              ..filter = ['owner', '=', 7]
              ..expression = [
                '|',
                [
                  ['a', '=', 1],
                  ['b', '=', 2],
                ],
              ]
              ..setQuick('late', true)
              ..search = '  lamp ';
          },
        ),
        [
          ['kind', '=', 1],
          ['owner', '=', 7],
          [
            '|',
            [
              ['a', '=', 1],
              ['b', '=', 2],
            ],
          ],
          ['late', 'is true'],
          [
            '|',
            [
              ['name', 'icontains', 'lamp'],
              ['code', 'icontains', 'lamp'],
            ],
          ],
        ],
      );
    });

    test(
      'keeps a single rule of the screen as one item, and drops what is empty',
      () async {
        expect(
          await filterOf(
            () => DataIterator<Thing>(
              api,
              filter: ['kind', '=', 1],
              searchFields: ['name'],
            ),
            (list) {
              list
                ..filter = []
                ..search = 'lamp';
            },
          ),
          [
            ['kind', '=', 1],
            ['name', 'icontains', 'lamp'],
          ],
        );
      },
    );

    test('follows a filter of the screen that changes: back to the first page, one read', () async {
      final kind = ValueNotifier<Object?>(['kind', '=', 1]);
      final list = DataIterator<Thing>(api, filter: kind);

      await settle();
      list.currentPage = 2;
      await settle();
      kind.value = ['kind', '=', 2];
      await settle();

      expect(server.lists, hasLength(3));
      expect(sent(server.lists.last)['offset'], 0);
      expect(sent(server.lists.last)['filter'], ['kind', '=', 2]);
      expect(list.currentPage, 1);

      list.dispose();
    });

    test('reads once for the changes of one turn', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      list
        ..expression = ['name', '=', 'a']
        ..orderBy = ['name:desc']
        ..pageSize = 25;
      await settle();

      expect(server.lists, hasLength(2));
      expect(sent(server.lists.last), {
        'offset': 0,
        'limit': 25,
        'filter': [
          ['name', '=', 'a'],
        ],
        'fields': 'id',
        'order': 'name:desc',
      });

      list.dispose();
    });
  });

  group('pages', () {
    test('reads the page it is on, the size changed reading the first one again, even from there', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      list.currentPage = 3;
      await settle();
      list.pageSize = 100;
      await settle();
      list.pageSize = 25;
      await settle();

      expect(server.lists.map((one) => sent(one)['offset']), [0, 100, 0, 0]);
      expect(server.lists.map((one) => sent(one)['limit']), [50, 50, 100, 25]);

      list.dispose();
    });

    test('reads again the page it shows, not the first one', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      list.currentPage = 3;
      await settle();
      await list.refresh();

      expect(sent(server.lists.last), {
        'offset': 100,
        'limit': 50,
        'filter': null,
        'fields': 'id',
        'order': null,
      });

      list.dispose();
    });

    test('adds the next page on loadMore, even when it pages, and reads them again together', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      await list.loadMore();

      expect(list.items, hasLength(100));
      expect(list.currentPage, 2);

      await list.refresh();

      expect(sent(server.lists.last)['offset'], 0);
      expect(sent(server.lists.last)['limit'], 100);
      expect(list.items, hasLength(100));

      list.dispose();
    });

    test('says there is nothing more on the last page', () async {
      server.rows = 70;
      final list = DataIterator<Thing>(api);

      await settle();
      expect(list.hasMore, isTrue);

      list.currentPage = 2;
      await settle();

      expect(list.hasMore, isFalse);
      expect(list.totalPages, 2);

      list.dispose();
    });

    test('reads the pages of the url at once when it appends, and keeps the next one in the url', () async {
      final url = MemoryListUrl(initial: {'p': '3'});
      final list = DataIterator<Thing>(api, append: true, url: url);

      await settle();

      expect(sent(server.lists.single)['offset'], 0);
      expect(sent(server.lists.single)['limit'], 150);
      expect(list.items, hasLength(120));

      server.rows = 400;
      await list.refresh();
      await list.loadMore();
      await settle();

      expect(url.query['p'], '4');
      expect(sent(server.lists.last)['offset'], 150);
      expect(list.items, hasLength(200));

      list.dispose();
    });

    test('reaches a row further down the list', () async {
      final list = DataIterator<Thing>(api, append: true);

      await settle();
      final row = await list.reach(110);

      expect(row?.id, 110);
      expect(list.items, hasLength(120));
      expect(await list.reach(999), isNull);

      list.dispose();
    });

    test(
      'keeps the size chosen on the device, and reads once it is known',
      () async {
        SharedPreferences.setMockInitialValues({'things-size': 25});
        final list = DataIterator<Thing>(api, pageSizeKey: 'things-size');

        await settle();

        expect(server.lists.single.queryParameters['limit'], 25);

        list.pageSize = 100;
        await settle();

        expect(
          (await SharedPreferences.getInstance()).getInt('things-size'),
          100,
        );

        list.dispose();
      },
    );
  });

  group('the order', () {
    test(
      'goes back to its default order on the third click on a column',
      () async {
        final list = DataIterator<Thing>(api, defaultOrderBy: ['id:asc']);

        await settle();
        list.toggleSort('name');
        expect(list.orderBy, ['name:asc']);
        list.toggleSort('name');
        expect(list.orderBy, ['name:desc']);
        expect(list.getSortDirection('name'), SortDirection.desc);
        list.toggleSort('name');
        expect(list.orderBy, ['id:asc']);
        expect(list.getSortDirection('name'), isNull);

        list.toggleSort('id');
        expect(list.orderBy, ['id:desc']);
        list.toggleSort('id');
        expect(list.orderBy, ['id:asc']);

        list.dispose();
      },
    );

    test(
      'reads a term without a direction as ascending, as the server does',
      () async {
        final list = DataIterator<Thing>(
          api,
          url: MemoryListUrl(initial: {'order_by': 'name'}),
        );

        await settle();

        expect(sent(server.lists.single)['order'], 'name');
        expect(list.getSortDirection('name'), SortDirection.asc);

        list.toggleSort('name');
        expect(list.orderBy, ['name:desc']);

        list.dispose();
      },
    );

    test('does not sort when it is not orderable', () async {
      final list = DataIterator<Thing>(api, orderable: false);

      list.toggleSort('name');

      expect(list.orderBy, isNull);

      list.dispose();
    });
  });

  group('the url', () {
    test(
      'reads the state of the list from the url, and writes what moves',
      () async {
        final url = MemoryListUrl(
          initial: {
            'p': '2',
            's': '25',
            'order_by': 'name:desc',
            'q': 'lamp',
            'f': jsonEncode(['name', '=', 'a']),
          },
        );
        final list = DataIterator<Thing>(
          api,
          url: url,
          defaultOrderBy: ['id:asc'],
        );

        await settle();

        expect(sent(server.lists.single), {
          'offset': 25,
          'limit': 25,
          'filter': [
            ['name', '=', 'a'],
            ['search_value', 'search_fuzzy', 'lamp'],
          ],
          'fields': 'id',
          'order': 'name:desc',
        });

        list
          ..orderBy = ['id:asc']
          ..expression = null
          ..search = '';
        await Future<void>.delayed(const Duration(milliseconds: 310));
        await settle();

        expect(url.query, {'s': '25'});

        list.dispose();
      },
    );

    test(
      'ignores an expression, a view or a page of the url that do not read',
      () async {
        final list = DataIterator<Thing>(
          api,
          url: MemoryListUrl(initial: {'f': '[not json', 'cv': 'x', 'p': '-2'}),
        );

        await settle();

        expect(list.expression, isNull);
        expect(list.view, isNull);
        expect(list.currentPage, 1);
        expect(sent(server.lists.single)['filter'], isNull);

        list.dispose();
      },
    );

    test('reads the filter of older links as its expression', () async {
      final list = DataIterator<Thing>(
        api,
        url: MemoryListUrl(
          initial: {
            'filter': jsonEncode(['name', '=', 'a']),
          },
        ),
      );

      await settle();

      expect(list.expression, ['name', '=', 'a']);

      list.dispose();
    });

    test('keeps its keys after its prefix, two lists of one screen writing together', () async {
      final url = MemoryListUrl(initial: {'done_q': 'lamp', 'p': '2'});
      final open = DataIterator<Thing>(api, url: url);
      final done = DataIterator<Thing>(api, url: url.withPrefix('done_'));

      await settle();

      expect(open.currentPage, 2);
      expect(done.search, 'lamp');
      expect(done.currentPage, 1);

      open.currentPage = 3;
      done.currentPage = 2;
      await settle();

      expect(url.query, {'done_q': 'lamp', 'p': '3', 'done_p': '2'});

      open.dispose();
      done.dispose();
    });

    test('follows the url when it changes from outside, in one read', () async {
      final url = MemoryListUrl();
      final list = DataIterator<Thing>(api, url: url);

      await settle();
      url.go({'p': '2', 'q': 'lamp', 'order_by': 'name:asc'});
      await settle();

      expect(list.currentPage, 2);
      expect(list.search, 'lamp');
      expect(list.orderBy, ['name:asc']);
      expect(server.lists, hasLength(2));
      expect(sent(server.lists.last), {
        'offset': 50,
        'limit': 50,
        'filter': [
          ['search_value', 'search_fuzzy', 'lamp'],
        ],
        'fields': 'id',
        'order': 'name:asc',
      });

      list.dispose();
    });

    test(
      'does not take its own writes landing late for a change from outside',
      () async {
        final url = MemoryListUrl();
        final list = DataIterator<Thing>(api, url: url);

        await settle();
        list.currentPage = 2;
        list.currentPage = 3;
        await settle();

        expect(url.query, {'p': '3'});
        expect(server.lists, hasLength(2));

        list.dispose();
      },
    );

    test('holds everything in memory without a url', () async {
      final list = DataIterator<Thing>(api);

      await settle();
      list.currentPage = 2;
      await settle();

      expect(list.currentPage, 2);

      list.dispose();
    });
  });
}

/// A list whose fields come from the screen, which tells it they changed.
class _Fields extends DataIterator<Thing> {
  _Fields(super.api, List<String> Function() fields)
    : super(fieldsResolver: fields);

  void touch() => fieldsChanged();
}
