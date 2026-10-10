/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

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

  ApiOptions<Thing> optionsOf({
    Object? filter,
    Object? query,
    int limit = 50,
  }) => ApiOptions<Thing>(
    api,
    fields: ['name'],
    filter: filter,
    query: query,
    limit: limit,
    minSearchLength: 2,
    searchFilter: (text) => ['name', 'icontains', text],
  );

  test(
    'reads nothing before its first search, then the fields shown and the id',
    () async {
      final options = optionsOf();

      await settle();
      expect(server.lists, isEmpty);

      await options.search();

      expect(sent(server.lists.single)['fields'], 'id,name');
      expect(sent(server.lists.single)['filter'], isNull);
      expect(options.items, hasLength(50));

      options.dispose();
    },
  );

  test(
    'leaves a text shorter than asked alone, and joins a search to its filter',
    () async {
      final kind = ValueNotifier<Object?>(['kind', '=', 1]);
      final options = optionsOf(filter: kind, query: {'balance': 'true'});

      await options.search('l');
      expect(server.lists, isEmpty);

      await options.search('lamp');

      expect(sent(server.lists.single)['filter'], [
        '&',
        [
          ['kind', '=', 1],
          ['name', 'icontains', 'lamp'],
        ],
      ]);
      expect(server.lists.single.queryParameters['balance'], 'true');

      kind.value = ['kind', '=', 2];
      await options.refresh();

      expect((sent(server.lists.last)['filter'] as List)[1], [
        ['kind', '=', 2],
        ['name', 'icontains', 'lamp'],
      ]);

      options.dispose();
    },
  );

  test('continues where it stopped, until there is no more', () async {
    server.rows = 70;
    final options = optionsOf();

    await options.search();
    expect(options.hasMore, isTrue);

    await options.loadMore();

    expect(options.items, hasLength(70));
    expect(options.hasMore, isFalse);
    expect(sent(server.lists.last)['offset'], 50);

    await options.loadMore();
    expect(server.lists, hasLength(2));

    options.dispose();
  });

  test('keeps the latest search when an earlier one answers after it, and shows nothing for a failed one', () async {
    final options = optionsOf();
    final slow = Completer<void>();

    server.gates.add(slow);
    final first = options.search('old');

    await settle();
    server.rows = 3;
    await options.search('new');
    slow.complete();
    await first;

    expect(options.items, hasLength(3));

    server.answer = (request) => const MockResponse.error(500);
    await options.search('down');

    expect(options.items, isEmpty);
    expect(options.hasMore, isFalse);

    options.dispose();
  });

  test(
    'reads back the record a field holds by its id, null when it cannot',
    () async {
      server.answer = (request) => request.path.endsWith('/things/7')
          ? const MockResponse.json({'id': 7, 'name': 'Lamp'})
          : const MockResponse.error(404);
      final options = optionsOf();

      expect((await options.resolve(7))?.data['name'], 'Lamp');
      expect(server.requests.single.headers['X-Fields'], 'id,name');
      expect(await options.resolve(8), isNull);

      options.dispose();
    },
  );
}
