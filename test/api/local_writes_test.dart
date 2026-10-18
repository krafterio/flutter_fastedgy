/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi({required Fetcher fetcher})
    : super('', modelName: 'thing', apiName: 'things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late Map<int, Map<String, Object?>> stored;
  late Completer<void> server;
  late MockResponse? refusal;
  late _ThingApi api;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    stored = {
      7: {'id': 7, 'name': 'Krafter', 'city': 'Lyon'},
      8: {'id': 8, 'name': 'Acme', 'city': 'Paris'},
    };
    server = Completer<void>()..complete();
    refusal = null;
    api = _ThingApi(
      fetcher: createMockFetcher(
        (request) async {
          requests.add(request);

          final id = int.tryParse(request.path.split('/').last);

          if (request.method == 'GET') {
            final filter = request.headers['X-Filter'] as String?;
            final rule = filter == null || filter.isEmpty
                ? null
                : jsonDecode(filter) as List;
            final ids = rule != null && rule[0] == 'id' ? rule[2] as List : null;
            final rows = [
              for (final row in stored.values)
                if (ids == null || ids.contains(row['id'])) row,
            ];

            return id == null
                ? MockResponse.json({
                    'items': rows,
                    'total': rows.length,
                    'limit': 50,
                    'offset': 0,
                  })
                : MockResponse.json(stored[id]);
          }

          await server.future;

          final refused = refusal;

          if (refused != null) {
            return refused;
          }

          final body = request.body as Map<String, dynamic>?;

          return switch (request.method) {
            'PATCH' => MockResponse.json(
              stored[id!] = {...?stored[id], ...?body},
            ),
            'DELETE' => MockResponse.empty(
              statusCode: stored.remove(id) == null ? 404 : 204,
            ),
            _ => MockResponse.json(stored[9] = {'id': 9, ...?body}),
          };
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  /// Holds the writes until [release].
  void hold() => server = Completer<void>();

  void release() => server.complete();

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<ApiRecord<_Thing>> record() async {
    final record = ApiRecord<_Thing>(api, fields: const ['id', 'name', 'city']);

    addTearDown(record.dispose);
    await record.load(7);

    return record;
  }

  Future<ApiCollection<_Thing>> collection() async {
    final collection = ApiCollection<_Thing>(
      api,
      fields: const ['id', 'name', 'city'],
    );

    addTearDown(collection.dispose);
    await collection.load();

    return collection;
  }

  List<String?> names(ApiCollection<_Thing> collection) => [
    for (final one in collection.items) one.getString('name'),
  ];

  group('a record', () {
    test(
      'shows a value before the server answers, then the record saved',
      () async {
        final thing = await record();

        hold();
        final write = thing.update({'name': 'Krafter SAS'});
        await settle();

        expect(thing.value?.getString('name'), 'Krafter SAS');
        expect(requests.last.method, 'PATCH');
        expect(requests.last.body, {'name': 'Krafter SAS'});

        release();
        await write;

        expect(thing.value?.getString('name'), 'Krafter SAS');
        expect(thing.value?.getString('city'), 'Lyon');
      },
    );

    test('a refusal puts back what it showed and is thrown', () async {
      final thing = await record();

      refusal = const MockResponse.error(422, body: {'detail': 'name_taken'});

      await expectLater(
        thing.update({'name': 'Acme'}),
        throwsA(isA<HttpError>()),
      );

      expect(thing.value?.getString('name'), 'Krafter');
    });

    test('reads its record once its own write is over, the value shown kept until then', () async {
      final thing = await record();
      final reads = requests.where((request) => request.method == 'GET').length;

      hold();
      final write = thing.update({'city': 'Grenoble'});
      await settle();

      expect(requests.where((request) => request.method == 'GET').length, reads);

      release();
      await write;
      await settle();

      expect(requests.where((request) => request.method == 'GET').length, reads + 1);
      expect(thing.value?.getString('city'), 'Grenoble');
    });

    test('a list holding it shows the value as soon as the record does, and gets it back on a refusal', () async {
      final thing = await record();
      final list = await collection();

      hold();
      final write = thing.update({'name': 'Krafter SAS'});
      await settle();

      expect(names(list), ['Krafter SAS', 'Acme']);

      refusal = const MockResponse.error(500);
      release();
      await expectLater(write, throwsA(isA<HttpError>()));
      await settle();

      expect(names(list), ['Krafter', 'Acme']);
      expect(thing.value?.getString('name'), 'Krafter');
    });

    test('a deletion leaves every list at once, and the record once the server said', () async {
      final thing = await record();
      final list = await collection();

      hold();
      final delete = thing.delete();
      await settle();

      expect(names(list), ['Acme']);
      expect(thing.isDeleted, isFalse);

      release();
      await delete;

      expect(thing.isDeleted, isTrue);
    });
  });

  test('a route of its own shows its values on every holder while it runs, and a refusal puts them back', () async {
    final thing = await record();
    final list = await collection();
    final route = Completer<void>();

    final write = thing.updateWith({'city': 'Annecy'}, (sent) async {
      expect(sent, {'city': 'Annecy'});
      await route.future;

      throw StateError('refused');
    });
    await settle();

    expect(thing.value?.getString('city'), 'Annecy');
    expect(list.byId(7)?.getString('city'), 'Annecy');

    route.complete();
    await expectLater(write, throwsStateError);
    await settle();

    expect(thing.value?.getString('city'), 'Lyon');
    expect(list.byId(7)?.getString('city'), 'Lyon');
  });

  group('a list', () {
    test(
      'a row deleted leaves at once, and comes back at its place on a refusal',
      () async {
        final list = await collection();

        hold();
        final delete = list.deleteItem(list.byId(7)!);
        await settle();

        expect(names(list), ['Acme']);
        expect(list.total, 1);

        refusal = const MockResponse.error(403);
        release();
        await expectLater(delete, throwsA(isA<HttpError>()));

        expect(names(list), ['Krafter', 'Acme']);
        expect(list.total, 2);
      },
    );

    test(
      'a row edited shows its value at once, on the record open too',
      () async {
        final list = await collection();
        final thing = await record();

        hold();
        final write = list.updateItem(list.byId(7)!, {'city': 'Annecy'});
        await settle();

        expect(list.byId(7)?.getString('city'), 'Annecy');
        expect(thing.value?.getString('city'), 'Annecy');

        release();
        await write;

        expect(list.byId(7)?.getString('city'), 'Annecy');
      },
    );

    test('reads its rows once its own write is over: the server may have moved them', () async {
      final list = await collection();
      int reads() => requests.where((request) => request.method == 'GET').length;
      final before = reads();

      await list.updateItem(list.byId(7)!, {'city': 'Annecy'});
      await list.updateItem(list.byId(8)!, {'city': 'Nice'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(reads(), before + 1);
    });

    test('an update named elsewhere reads its row alone; a row the filter left goes', () async {
      final list = await collection();
      List<MockRequest> reads() => [
        for (final request in requests)
          if (request.method == 'GET') request,
      ];
      final before = reads().length;

      stored[7] = {...stored[7]!, 'name': 'Krafter SAS'};
      stored.remove(8);
      getService<Bus>()
        ..fire(
          const ResourceChangedEvent(
            null,
            model: 'thing',
            type: ResourceChangeType.updated,
            id: 7,
            fields: {'name'},
            announced: true,
          ),
        )
        ..fire(
          const ResourceChangedEvent(
            null,
            model: 'thing',
            type: ResourceChangeType.updated,
            id: 8,
            fields: {'city'},
            announced: true,
          ),
        );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(reads(), hasLength(before + 1));
      expect(reads().last.headers['X-Filter'], jsonEncode(['id', 'in', [7, 8]]));
      expect(names(list), ['Krafter SAS']);
      expect(list.total, 1);
    });

    test('an update moving the order reads the whole range again', () async {
      final list = ApiCollection<_Thing>(api, fields: const ['id', 'name'], orderBy: const ['name']);

      addTearDown(list.dispose);
      await list.load();

      getService<Bus>().fire(
        const ResourceChangedEvent(
          null,
          model: 'thing',
          type: ResourceChangeType.updated,
          id: 7,
          fields: {'name'},
          announced: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(requests.last.headers['X-Filter'], anyOf(isNull, isEmpty));
    });

    test('a record created joins the rows once the server answers', () async {
      final list = await collection();

      final created = await list.createItem({'name': 'Globex'}, prepend: true);

      expect(created.id, 9);
      expect(names(list), ['Globex', 'Krafter', 'Acme']);
      expect(list.total, 3);
    });
  });
}
