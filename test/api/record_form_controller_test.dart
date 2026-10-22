/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';

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
    stored = {
      'id': 7,
      'name': 'Krafter',
      'city': 'Lyon',
      'avatar': null,
      'preferences': {'compact': false, 'theme': 'dark'},
    };
    refuse = false;

    final fetcher = createMockFetcher(
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

        if (request.path.startsWith('/storage/upload/')) {
          return const MockResponse.json({'path': 'things/7/avatar.png'});
        }

        return MockResponse.json(
          stored = {...stored, ...?(request.body as Map<String, dynamic>?)},
        );
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _ThingApi(fetcher: fetcher);

    if (hasService<StorageUploader>()) {
      container.unregister<StorageUploader>();
    }

    container.registerSingleton<StorageUploader>(StorageUploader(fetcher));
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<ApiRecord<_Thing>> record() async {
    final record = ApiRecord<_Thing>(
      api,
      fields: const ['id', 'name', 'city', 'avatar', 'preferences'],
    );

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

  test('saves on their own the fields that say so, alone, and the others when asked', () async {
    final form = RecordFormController(await record());

    addTearDown(form.dispose);

    form.set('city', 'Paris');
    form.set('name', 'Krafter SAS', autoSave: true);
    await settle();

    expect(writes().single.body, {'name': 'Krafter SAS'});
    expect(form.changes, {'city': 'Paris'});

    expect(await form.save(), isTrue);
    expect(writes().last.body, {'city': 'Paris'});
  });

  test(
    'saves nothing on its own once not allowed to, whatever a field says',
    () async {
      final form = RecordFormController(
        await record(),
        autoSave: true,
        allowAutoSave: false,
      );

      addTearDown(form.dispose);

      form.set('city', 'Paris', autoSave: true);
      await settle();

      expect(writes(), isEmpty);
      expect(form.dirty, isTrue);
    },
  );

  test(
    'a field that says no is not saved on its own by a form that saves',
    () async {
      final form = RecordFormController(await record(), autoSave: true);

      addTearDown(form.dispose);

      form.set('city', 'Paris', autoSave: false);
      await settle();

      expect(writes(), isEmpty);
    },
  );

  test('edits a key of a JSON field, written as the whole of it', () async {
    final form = RecordFormController(await record());

    addTearDown(form.dispose);

    expect(form['preferences.compact'], isFalse);

    form.set('preferences.compact', true);

    expect(form['preferences.compact'], isTrue);
    expect(await form.save(), isTrue);
    expect(writes().single.body, {
      'preferences': {'compact': true, 'theme': 'dark'},
    });
    expect(form.dirty, isFalse);
  });

  test(
    'stores a file before writing its path in its field, and reports the save',
    () async {
      final form = RecordFormController(await record());
      final saves = <RecordFormSave>[];

      addTearDown(form.dispose);
      form.saves.listen(saves.add);

      form.set(
        'avatar',
        RecordFormFile(bytes: Uint8List.fromList([1, 2, 3]), name: 'me.png'),
      );

      expect(await form.save(), isTrue);
      await settle();

      final [upload, patch] = [
        for (final request in requests)
          if (request.method != 'GET') request,
      ];

      expect(upload.path, '/storage/upload/thing/7/avatar');
      expect(patch.body, {'avatar': 'things/7/avatar.png'});
      expect(saves.single.fields, {'avatar'});
      expect((saves.single.auto, saves.single.saved), (false, true));
    },
  );

  test(
    'reads and writes the record of an api through a record of its own',
    () async {
      final form = RecordFormController.api(
        api,
        7,
        fields: const ['id', 'name'],
      );

      await settle();

      expect(form['name'], 'Krafter');

      form.set('name', 'Krafter SAS');

      expect(await form.save(), isTrue);
      expect(writes().single.body, {'name': 'Krafter SAS'});

      form.dispose();
      await settle();
    },
  );

  test(
    'a save asked for says what to fix in place of writing, and is reported',
    () async {
      final form = RecordFormController(
        await record(),
        validate: (form) =>
            (form['name'] as String?)?.isEmpty ?? true ? 'Name it' : null,
      );
      final saves = <RecordFormSave>[];

      addTearDown(form.dispose);
      form.saves.listen(saves.add);

      form.set('name', '');

      expect(await form.save(), isFalse);
      await settle();

      expect(writes(), isEmpty);
      expect('${form.error}', 'Name it');
      expect(saves.single.error, isA<RecordFormInvalid>());
    },
  );

  test(
    'a save asked for with nothing changed is reported, as written',
    () async {
      final form = RecordFormController(await record());
      final saves = <RecordFormSave>[];

      addTearDown(form.dispose);
      form.saves.listen(saves.add);

      expect(await form.save(), isTrue);
      await settle();

      expect(writes(), isEmpty);
      expect(saves.single.fields, isEmpty);
      expect(saves.single.saved, isTrue);
    },
  );
}
