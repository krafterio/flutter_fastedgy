/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

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
  late _ThingApi api;
  late ApiRecord<_Thing> thing;

  setUp(() async {
    await container.reset(dispose: false);
    container
      ..registerSingleton<Bus>(Bus())
      ..registerSingleton<MetadataProvider>(
        FakeMetadataProvider({
          'thing': metaModel(
            'thing',
            fields: {
              'name': metaField('name', type: 'char', label: 'Name'),
              'mail': metaField('mail', type: 'email', label: 'Mail'),
              'code': metaField('code', type: 'char', readonly: true),
              'data': metaField('data', type: 'json'),
            },
          ),
        }),
      );

    container
      ..registerSingleton<RecordFormInputs>(RecordFormInputs())
      ..registerSingleton<RecordFormFeedback>(const RecordFormFeedback());

    final stored = <String, Object?>{
      'id': 1,
      'name': 'Lamp',
      'mail': 'a@b.c',
      'data': {'compact': true},
    };

    api = _ThingApi(
      fetcher: createMockFetcher(
        (request) async => MockResponse.json(stored),
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
    thing = ApiRecord<_Thing>(api);
    addTearDown(thing.dispose);
    await thing.load(1);
  });

  Widget input(BuildContext context, RecordFormInput input) => GestureDetector(
    onTap: () => input.set('${input.value}!'),
    child: Text(
      '${input.label}: ${input.value} ${input.enabled ? 'on' : 'off'}',
    ),
  );

  Future<RecordFormController<_Thing>> pumpForm(
    WidgetTester tester,
    List<Widget> fields,
  ) async {
    final form = RecordFormController(thing);

    addTearDown(form.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RecordForm.controlled(
          controller: form,
          child: Column(children: fields),
        ),
      ),
    );
    await tester.pump();

    return form;
  }

  testWidgets('draws nothing for a field no input is registered for', (
    tester,
  ) async {
    await pumpForm(tester, const [RecordFormField('name')]);

    expect(find.byType(Text), findsNothing);
  });

  testWidgets(
    'draws a field with the input of its type, else of its kind, and writes it back',
    (tester) async {
      getService<RecordFormInputs>()
        ..register(FieldKind.text, input)
        ..registerType(
          'email',
          (context, input) => Text('mail ${input.value}'),
        );

      final form = await pumpForm(tester, const [
        RecordFormField('name'),
        RecordFormField('mail'),
        RecordFormField('code', label: 'Code'),
        RecordFormField('data'),
      ]);

      expect(find.text('Name: Lamp on'), findsOneWidget);
      expect(find.text('mail a@b.c'), findsOneWidget);
      expect(find.text('Code: null off'), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(3));

      await tester.tap(find.text('Name: Lamp on'));
      await tester.pump();

      expect(form.changes, {'name': 'Lamp!'});
      expect(find.text('Name: Lamp! on'), findsOneWidget);
    },
  );

  testWidgets(
    'draws a field with the input given with its settings, a key of a JSON field with its type and default',
    (tester) async {
      getService<RecordFormInputs>()
        ..registerInput<_Shout>(
          (context, field, input) => Text('${field.value}${input.mark}'),
        )
        ..register(
          FieldKind.boolean,
          (context, input) => Text('${input.field.name} ${input.value}'),
        );

      await pumpForm(tester, const [
        RecordFormField('name', input: _Shout('!')),
        RecordFormField('data.compact', type: 'boolean'),
        RecordFormField('data.other', type: 'boolean', defaultValue: true),
        RecordFormField('data.unknown'),
      ]);

      expect(find.text('Lamp!'), findsOneWidget);
      expect(find.text('data.compact true'), findsOneWidget);
      expect(find.text('data.other true'), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(3));
    },
  );

  testWidgets('a guard leaves the field as it is when it refuses a value', (
    tester,
  ) async {
    getService<RecordFormInputs>().register(FieldKind.text, input);

    final form = await pumpForm(tester, [
      RecordFormField('name', guard: (value) => value != 'Lamp!'),
    ]);

    await tester.tap(find.text('Name: Lamp on'));
    await tester.pump();

    expect(form.dirty, isFalse);
  });

  testWidgets(
    'tells the feedback of the container each save of a form of its own, on its own for the fields that say so',
    (tester) async {
      final told = <RecordFormSave>[];

      container
        ..unregister<RecordFormFeedback>()
        ..registerSingleton<RecordFormFeedback>(_Feedback(told));
      getService<RecordFormInputs>().register(FieldKind.text, input);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RecordForm.api(
            api: api,
            id: 1,
            child: const Column(
              children: [RecordFormField('name', autoSave: true)],
            ),
          ),
        ),
      );
      for (var turn = 0; turn < 10; turn++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.tap(find.text('Name: Lamp on'));
      for (var turn = 0; turn < 10; turn++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(told.single.fields, {'name'});
      expect((told.single.auto, told.single.saved), (true, true));
    },
  );
  testWidgets('tells its own feedback in place of the one of the container', (
    tester,
  ) async {
    final told = <RecordFormSave>[];
    final global = <RecordFormSave>[];

    container
      ..unregister<RecordFormFeedback>()
      ..registerSingleton<RecordFormFeedback>(_Feedback(global));
    getService<RecordFormInputs>().register(FieldKind.text, input);

    final form = RecordFormController(thing);

    addTearDown(form.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RecordForm.controlled(
          controller: form,
          feedback: _Feedback(told),
          child: const RecordFormField('name'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Name: Lamp on'));
    await tester.runAsync(form.save);
    await tester.pump();

    expect((told.length, global.length), (1, 0));
  });
}

class _Shout extends FieldInput {
  const _Shout(this.mark);

  final String mark;
}

class _Feedback extends RecordFormFeedback {
  _Feedback(this.told);

  final List<RecordFormSave> told;

  @override
  void show(BuildContext context, RecordFormSave save) => told.add(save);
}
