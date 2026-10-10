/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart' show WorkspaceSwitchedEvent;
import 'package:flutter_test/flutter_test.dart';

import 'list_support.dart';

class _Me extends BaseModel<_Me> {
  _Me(super.data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ViewServer views;
  late ThingApi api;

  setUp(() async {
    await setUpList();
    server = ThingServer();
    views = ViewServer(server);
    api = ThingApi(server.fetcher);
  });

  List<MockRequest> viewReads() => [
    for (final request in server.requests)
      if (request.method == 'GET' && request.path.contains('/custom_view'))
        request,
  ];

  Map<String, dynamic> lastWrite() => Map<String, dynamic>.from(
    server.requests
            .lastWhere(
              (request) =>
                  request.method != 'GET' &&
                  request.path.contains('/custom_view'),
            )
            .body
        as Map,
  );

  group('the custom views of a list', () {
    test(
      'reads the views of its list once, and the favorite of the user',
      () async {
        final mine = views.add({'name': 'Mine'});

        views.add({'name': 'Other list', 'scope': 'archive'});
        views.favorites.add({'id': 1, 'view': mine['id']});

        final list = DataIterator<Thing>(api);
        final custom = CustomViews('thing', list: list);

        await Future.wait([custom.ensure(), custom.ensure()]);
        await custom.ensure();

        expect(custom.items.map((view) => view.name), ['Mine']);
        expect(custom.favorite, mine['id']);
        expect(viewReads(), hasLength(2));
        expect(viewReads().first.path, '/acme/custom_views');

        list.dispose();
      },
    );

    test('applies a view to its list, keeping the search, and tells when the list moves away', () async {
      final late = views.add({
        'name': 'Late',
        'filters': ['late', 'is true'],
        'order_by': ['name:desc'],
      });
      final url = MemoryListUrl();
      final list = DataIterator<Thing>(
        api,
        url: url,
        defaultOrderBy: ['id:asc'],
      );
      final custom = CustomViews('thing', list: list);

      await custom.ensure();
      await settle();
      list.search = 'lamp';
      await Future<void>.delayed(const Duration(milliseconds: 310));
      await settle();

      custom.apply(custom.items.single);
      await settle();

      expect(list.view, late['id']);
      expect(list.expression, ['late', 'is true']);
      expect(list.orderBy, ['name:desc']);
      expect(list.search, 'lamp');
      expect(custom.current?.name, 'Late');
      expect(custom.modified, isFalse);
      expect(url.query, {
        'q': 'lamp',
        'order_by': 'name:desc',
        'cv': '${late['id']}',
      });
      expect(sent(server.lists.last)['filter'], [
        ['late', 'is true'],
        ['search_value', 'search_fuzzy', 'lamp'],
      ]);

      list.expression = ['late', 'is false'];
      await settle();

      expect(custom.modified, isTrue);
      expect(jsonDecode(url.query['f']!), ['late', 'is false']);
      expect(canUpdateView(custom), isTrue);

      list.dispose();
    });

    test('keeps what the list shows as a view, shared or for the user alone, its scope left to the server when it is the default one', () async {
      container.registerSingleton<UserProvider<_Me>>(
        UserProvider<_Me>(() async => _Me({'id': 5})),
      );
      await getService<UserProvider<_Me>>().load();

      final list = DataIterator<Thing>(api, url: MemoryListUrl());
      final custom = CustomViews('thing', list: list);

      await settle();
      list.expression = ['name', '=', 'a'];
      await settle();

      final shared = await custom.create(name: 'Everyone');

      expect(lastWrite(), {
        'name': 'Everyone',
        'model': 'thing',
        'user': null,
        'filters': ['name', '=', 'a'],
        'order_by': null,
      });
      expect(list.view, shared.id);
      expect(custom.current?.name, 'Everyone');

      await custom.create(name: 'Me', shared: false);

      expect(lastWrite()['user'], 5);

      final archive = CustomViews('thing', scope: 'archive', list: list);

      await archive.create(name: 'Archive');

      expect(lastWrite()['scope'], 'archive');

      list.dispose();
    });

    test('keeps one default for everyone, one favorite for the user, and lets a deleted view go', () async {
      final first = views.add({'name': 'First', 'is_default': true});
      final second = views.add({'name': 'Second'});
      final list = DataIterator<Thing>(api);
      final custom = CustomViews('thing', list: list);

      await custom.ensure();
      final [one, two] = custom.items;

      await custom.setDefault(two, true);

      expect(custom.items.map((view) => view.isDefault), [false, true]);

      await custom.setFavorite(one, true);

      expect(custom.favorite, first['id']);
      expect(views.favorites.single['view'], first['id']);

      await custom.setFavorite(one, false);

      expect(custom.favorite, isNull);
      expect(views.favorites, isEmpty);

      custom.apply(custom.items.last);
      await custom.remove(custom.items.last);

      expect(custom.items.map((view) => view.name), ['First']);
      expect(list.view, isNull);
      expect(views.views.map((view) => view['id']), [first['id']]);
      expect(second['id'], isNot(first['id']));

      list.dispose();
    });

    test(
      'applies and saves what the list holds besides its filters and its order',
      () async {
        Object? grouped;
        final view = views.add({'name': 'By status', 'group_by': 'status'});
        final list = DataIterator<Thing>(
          api,
          views: DataIteratorViews(
            state: {
              'group_by': ViewStateField(
                get: () => grouped,
                set: (value) => grouped = value,
                key: 'g',
              ),
            },
          ),
        );
        final custom = CustomViews('thing', list: list);

        await custom.ensure();
        custom.apply(custom.items.single);

        expect(grouped, 'status');
        expect(custom.modified, isFalse);

        grouped = 'owner';

        expect(custom.modified, isTrue);

        await custom.save(custom.items.single);

        expect(lastWrite()['group_by'], 'owner');
        expect(views.views.single['group_by'], 'owner');
        expect(view['id'], list.view);

        list.dispose();
      },
    );

    test('lets what the server refuses reach whoever saves', () async {
      final list = DataIterator<Thing>(api);
      final custom = CustomViews('thing', list: list);

      views.refuse = const MockResponse.error(
        422,
        body: {'detail': 'Name taken'},
      );

      await expectLater(
        custom.create(name: 'Twice'),
        throwsA(isA<HttpError>()),
      );
      expect(custom.items, isEmpty);

      list.dispose();
    });

    test('offers on a view what the user may do with it', () async {
      final shared = CustomView({'id': 1, 'editable': true, 'user': null});
      final own = CustomView({'id': 2, 'editable': true, 'user': 5});

      expect(viewActions(shared), [
        ViewAction.favoriteForEveryone,
        ViewAction.rename,
        ViewAction.delete,
      ]);
      expect(
        viewActions(CustomView({...shared.data, 'is_default': true})).first,
        ViewAction.notFavoriteForEveryone,
      );
      expect(viewActions(own), [ViewAction.rename, ViewAction.delete]);
      expect(viewActions(CustomView({'id': 3, 'editable': false})), isEmpty);
      expect(canSaveView(0), isFalse);
      expect(canSaveView(2), isTrue);
    });
  });

  group('the view a list opens on', () {
    test('is the favorite of the user before the one of everyone, read before the first page', () async {
      final mine = views.add({
        'name': 'Mine',
        'filters': ['owner', '=', 5],
      });

      views.add({
        'name': 'Everyone',
        'is_default': true,
        'filters': ['name', '=', 'a'],
      });
      views.favorites.add({'id': 1, 'view': mine['id']});

      final url = MemoryListUrl();
      final list = DataIterator<Thing>(
        api,
        url: url,
        views: const DataIteratorViews(),
      );

      await settle();

      expect(list.opened, isTrue);
      expect(list.view, mine['id']);
      expect(server.lists, hasLength(1));
      expect(sent(server.lists.single)['filter'], [
        ['owner', '=', 5],
      ]);
      expect(url.query, isEmpty);

      list.dispose();
    });

    test('falls back on the one of everyone, and reads none when the url already says what the list shows', () async {
      views.add({
        'name': 'Everyone',
        'is_default': true,
        'order_by': ['name:asc'],
      });

      final list = DataIterator<Thing>(api, views: const DataIteratorViews());

      await settle();

      expect(list.orderBy, ['name:asc']);
      expect(sent(server.lists.single)['order'], 'name:asc');

      final reads = viewReads().length;
      final described = DataIterator<Thing>(
        api,
        url: MemoryListUrl(initial: {'q': 'lamp'}),
        views: const DataIteratorViews(),
      );

      await settle();

      expect(viewReads(), hasLength(reads));
      expect(described.view, isNull);

      list.dispose();
      described.dispose();
    });

    test('opens a link on the view it names, read again, or without a view when it is not one of this list', () async {
      final named = views.add({
        'name': 'Named',
        'filters': ['name', '=', 'b'],
      });
      final other = views.add({'name': 'Other', 'scope': 'archive'});

      views.add({'name': 'Everyone', 'is_default': true});

      final list = DataIterator<Thing>(
        api,
        url: MemoryListUrl(initial: {'cv': '${named['id']}'}),
        views: const DataIteratorViews(),
      );
      final stray = DataIterator<Thing>(
        api,
        url: MemoryListUrl(initial: {'cv': '${other['id']}'}),
        views: const DataIteratorViews(),
      );

      await settle();

      expect(list.view, named['id']);
      expect(list.expression, ['name', '=', 'b']);
      expect(stray.view, isNull);
      expect(stray.expression, isNull);

      list.dispose();
      stray.dispose();
    });

    test('opens a link carrying its own filters on them, its view staying the current one', () async {
      final named = views.add({
        'name': 'Named',
        'filters': ['name', '=', 'b'],
      });
      final url = MemoryListUrl(
        initial: {
          'cv': '${named['id']}',
          'f': jsonEncode(['name', '=', 'c']),
        },
      );
      final list = DataIterator<Thing>(
        api,
        url: url,
        views: const DataIteratorViews(),
      );

      await settle();

      expect(list.view, named['id']);
      expect(list.expression, ['name', '=', 'c']);
      expect(viewReads(), isEmpty);

      list.dispose();
    });

    test('holds what its view says besides, unless the url says it', () async {
      Object? grouped;
      final named = views.add({'name': 'By status', 'group_by': 'status'});

      DataIterator<Thing> make(Map<String, String> query) =>
          DataIterator<Thing>(
            api,
            url: MemoryListUrl(initial: query),
            views: DataIteratorViews(
              state: {
                'group_by': ViewStateField(
                  get: () => grouped,
                  set: (value) => grouped = value,
                  key: 'g',
                ),
              },
            ),
          );

      final list = make({'cv': '${named['id']}'});

      await settle();
      expect(grouped, 'status');

      grouped = 'owner';
      final kept = make({'cv': '${named['id']}', 'g': 'owner'});

      await settle();
      expect(grouped, 'owner');

      list.dispose();
      kept.dispose();
    });

    test(
      'opens the view a url changed from outside names, in one read',
      () async {
        final named = views.add({
          'name': 'Named',
          'filters': ['name', '=', 'b'],
        });
        final url = MemoryListUrl(initial: {'q': 'x'});
        final list = DataIterator<Thing>(
          api,
          url: url,
          views: const DataIteratorViews(),
        );

        await settle();
        url.go({'cv': '${named['id']}'});
        await settle();

        expect(list.view, named['id']);
        expect(list.expression, ['name', '=', 'b']);
        expect(list.search, '');
        expect(server.lists, hasLength(2));
        expect(sent(server.lists.last)['filter'], [
          ['name', '=', 'b'],
        ]);

        list.dispose();
      },
    );

    test('opens again on the view of the workspace switched to', () async {
      final url = MemoryListUrl(initial: {'q': 'x'});
      final list = DataIterator<Thing>(
        api,
        url: url,
        views: const DataIteratorViews(),
      );

      await settle();
      final everyone = views.add({
        'name': 'Everyone',
        'is_default': true,
        'filters': ['name', '=', 'z'],
      });

      getService<Bus>().fire(const WorkspaceSwitchedEvent());
      await settle();

      expect(list.view, everyone['id']);
      expect(list.expression, ['name', '=', 'z']);
      expect(url.query, {'cv': '${everyone['id']}'});
      expect(server.lists, hasLength(2));

      list.dispose();
    });
  });
}
