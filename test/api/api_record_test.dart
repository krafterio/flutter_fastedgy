/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

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
  late MockResponse Function(MockRequest request) answer;
  late _ThingApi api;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    answer = (_) => const MockResponse.json({'id': 7, 'name': 'Krafter'});
    api = _ThingApi(
      fetcher: createMockFetcher(
        (request) {
          requests.add(request);

          return answer(request);
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  Future<ApiRecord<_Thing>> loaded() async {
    final record = ApiRecord<_Thing>(api);

    addTearDown(record.dispose);
    await record.load(7);

    return record;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  void fire(ResourceChangedEvent event) => getService<Bus>().fire(event);

  test(
    'shows its seed without a loader, then reads it again silently',
    () async {
      final record = ApiRecord<_Thing>(api);
      final loading = <bool>[];

      addTearDown(record.dispose);
      record.addListener(() => loading.add(record.isLoading));

      final load = record.load(7, seed: _Thing({'id': 7, 'name': 'Seed'}));

      expect(record.value?.data['name'], 'Seed');
      expect(record.isLoading, isFalse);

      await load;

      expect(requests.length, 1);
      expect(record.value?.data['name'], 'Krafter');
      expect(loading, everyElement(isFalse));
    },
  );

  test('keeps its seed without reading when told not to read again', () async {
    final record = ApiRecord<_Thing>(api);

    addTearDown(record.dispose);
    await record.load(
      7,
      seed: _Thing({'id': 7, 'name': 'Seed'}),
      reread: false,
    );

    expect(requests, isEmpty);
    expect(record.value?.data['name'], 'Seed');
  });

  test('re-reads on an event that names no record', () async {
    final record = await loaded();
    final before = requests.length;

    fire(const ResourceChangedEvent('/things'));
    await settle();

    expect(requests.length, before + 1);
    expect(record.isDeleted, isFalse);
  });

  test('leaves a write on another record alone', () async {
    await loaded();
    final before = requests.length;

    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 9,
      ),
    );
    await settle();

    expect(requests.length, before);
  });

  test('hears its record named as a string', () async {
    await loaded();
    final before = requests.length;

    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: '7',
      ),
    );
    await settle();

    expect(requests.length, before + 1);
  });

  test('says the record is gone on a delete naming it', () async {
    final record = await loaded();

    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.deleted,
        id: 7,
      ),
    );
    await settle();

    expect(record.isDeleted, isTrue);
    expect(record.value, isNull);
  });

  test('says the record is gone when a silent re-read answers 404', () async {
    final record = await loaded();

    answer = (_) => const MockResponse.error(404);
    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 7,
      ),
    );
    await settle();

    expect(record.isDeleted, isTrue);
  });

  test('stays deaf to another model on its own path', () async {
    await loaded();
    final before = requests.length;

    fire(const ResourceChangedEvent('/things', model: 'other'));
    await settle();

    expect(requests.length, before);
  });

  test('follows the id it is loaded with', () async {
    final record = await loaded();

    await record.load(9);

    final before = requests.length;

    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 7,
      ),
    );
    await settle();

    expect(requests.length, before);

    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 9,
      ),
    );
    await settle();

    expect(requests.length, before + 1);
  });

  test('reads itself again when the socket comes back', () async {
    await loaded();
    final before = requests.length;

    getService<Bus>().fire(const ResourcesStaleEvent());
    await settle();

    expect(requests.length, before + 1);
  });

  test('off screen, owes one read', () async {
    final record = await loaded();
    final before = requests.length;

    record.active = false;
    fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 7,
      ),
    );
    await settle();

    expect(requests.length, before);

    record.active = true;
    await settle();

    expect(requests.length, before + 1);
  });
}
