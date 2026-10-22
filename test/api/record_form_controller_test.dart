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
  late Map<String, Object?> stored;
  late bool refuse;
  late _ThingApi api;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    stored = {'id': 7, 'name': 'Krafter', 'city': 'Lyon'};
    refuse = false;
    api = _ThingApi(
      fetcher: createMockFetcher(
        (request) async {
          requests.add(request);

          if (request.method == 'GET') {
            return MockResponse.json(stored);
          }

          if (refuse) {
            return const MockResponse.json({
              'detail': 'Refused',
            }, statusCode: 422);
          }

          return MockResponse.json(
            stored = {...stored, ...?(request.body as Map<String, dynamic>?)},
          );
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<ApiRecord<_Thing>> record() async {
    final record = ApiRecord<_Thing>(api, fields: const ['id', 'name', 'city']);

    addTearDown(record.dispose);
    await record.load(7);

    return record;
  }

  List<MockRequest> writes() => [
    for (final request in requests)
      if (request.method == 'PATCH') request,
  ];

  test('follows the record where nothing is edited, keeps what is, and sends what changed alone', () async {
    final thing = await record();
    final form = RecordFormController(thing);

    addTearDown(form.dispose);

    form.set('name', 'Krafter SAS');

    expect(
      (form['name'], form['city'], form.dirty),
      ('Krafter SAS', 'Lyon', true),
    );

    stored = {...stored, 'name': 'Elsewhere', 'city': 'Paris'};
    await thing.reload();

    expect((form['name'], form['city']), ('Krafter SAS', 'Paris'));
    expect(writes(), isEmpty);

    expect(await form.save(), isTrue);

    expect(writes().single.body, {'name': 'Krafter SAS'});
    expect(form.dirty, isFalse);
    expect(thing.value?.getString('name'), 'Krafter SAS');
  });

  test('a value set back to the record\'s is no change', () async {
    final form = RecordFormController(await record());

    addTearDown(form.dispose);

    form.set('city', 'Paris');
    form.set('city', 'Lyon');

    expect(form.dirty, isFalse);
    expect(await form.save(), isTrue);
    expect(writes(), isEmpty);
  });

  test(
    'a refusal keeps what was edited and says why, to be saved again',
    () async {
      final form = RecordFormController(await record());

      addTearDown(form.dispose);

      refuse = true;
      form.set('name', 'Krafter SAS');

      expect(await form.save(), isFalse);
      expect((form['name'], form.dirty), ('Krafter SAS', true));
      expect(form.error, isNotNull);

      refuse = false;

      expect(await form.save(), isTrue);
      expect(form.error, isNull);
    },
  );

  test(
    'saves on its own: a choice at once, a text once the typing pauses',
    () async {
      final thing = await record();
      final form = RecordFormController(
        thing,
        autoSave: true,
        autoSaveDelay: const Duration(milliseconds: 50),
      );

      addTearDown(form.dispose);

      form.set('city', 'Paris');
      await settle();

      expect(writes().single.body, {'city': 'Paris'});

      form.set('name', 'K', typing: true);
      form.set('name', 'Kr', typing: true);
      await settle();

      expect(writes(), hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(writes().last.body, {'name': 'Kr'});
      expect(form.dirty, isFalse);
    },
  );

  test(
    'saving on its own, a refused value gives way to the record\'s',
    () async {
      final thing = await record();
      final form = RecordFormController(thing, autoSave: true);

      addTearDown(form.dispose);

      refuse = true;
      form.set('city', 'Paris');
      await settle();

      expect((form['city'], form.dirty), ('Lyon', false));
      expect(form.error, isNotNull);
    },
  );
}
