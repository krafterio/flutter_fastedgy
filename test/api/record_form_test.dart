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

  /// What the server answers a write with, when it refuses it.
  MockResponse? refusal;
  late List<MockRequest> writes;

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

    refusal = null;
    writes = [];
    api = _ThingApi(
      fetcher: createMockFetcher(
        (request) async {
          if (request.method != 'GET') {
            writes.add(request);
          }

          return request.method == 'GET'
              ? MockResponse.json(stored)
              : refusal ?? MockResponse.json(stored);
        },
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

  testWidgets('a field is told of each value it takes, to set another', (
    tester,
  ) async {
    getService<RecordFormInputs>().register(FieldKind.text, input);

    final form = await pumpForm(tester, [
      RecordFormField(
        'name',
        onChanged: (value) =>
            RecordForm.controllerOf(tester.element(find.byType(Column)))
                ?.set('mail', 'b@c.d'),
      ),
    ]);

    await tester.tap(find.text('Name: Lamp on'));
    await tester.pump();

    expect(form.changes, {'name': 'Lamp!', 'mail': 'b@c.d'});
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
  group('a refused save', () {
    Future<(RecordFormController<_Thing>, List<RecordFormSave>)> pumpRefused(
      WidgetTester tester, {
      bool alert = true,
      RecordFormFieldValidator? validator,
    }) async {
      final told = <RecordFormSave>[];

      getService<RecordFormInputs>().register(FieldKind.text, input);
      container
        ..unregister<RecordFormFeedback>()
        ..registerSingleton<RecordFormFeedback>(_Feedback(told));

      final form = RecordFormController(thing);

      addTearDown(form.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RecordForm.controlled(
            controller: form,
            child: Column(
              children: [
                if (alert) const RecordFormAlert(),
                RecordFormField('name', validator: validator),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      return (form, told);
    }

    Future<void> tapAndSave(
      WidgetTester tester,
      RecordFormController<_Thing> form,
    ) async {
      await tester.tap(find.text('Name: Lamp on'));
      await tester.pump();
      await tester.runAsync(form.save);
      await tester.pump();
    }

    testWidgets(
      'says the errors of the server under the fields they name, the others in its alert',
      (tester) async {
        refusal = const MockResponse.error(
          422,
          body: {
            'detail': [
              {
                'loc': ['body', 'name'],
                'msg': 'Too short',
                'type': 'value_error',
              },
              {
                'loc': ['body', 'mail'],
                'msg': 'Not a mail',
                'type': 'value_error',
              },
              {
                'loc': ['body'],
                'msg': 'Nothing changes',
                'type': 'value_error',
              },
            ],
          },
        );
        final (form, told) = await pumpRefused(tester);

        await tapAndSave(tester, form);

        expect(form.errorOf('name'), 'Too short');
        expect(find.text('Too short'), findsOneWidget);
        expect(form.alerts, ['Nothing changes', 'Mail: Not a mail']);
        expect(find.text('Mail: Not a mail'), findsOneWidget);
        expect(told.single.errors, {'name': 'Too short'});
        expect(told.single.alerted, isTrue);

        await tester.tap(find.text('Name: Lamp! on'));
        await tester.pump();

        expect(
          find.text('Too short'),
          findsNothing,
          reason: 'set again, the field lets go of its message',
        );
        expect(find.text('Mail: Not a mail'), findsOneWidget);
      },
    );

    testWidgets('leaves its alerts to the feedback when no alert shows them', (
      tester,
    ) async {
      refusal = const MockResponse.error(
        400,
        body: {'detail': 'Already taken'},
      );
      final (form, told) = await pumpRefused(tester, alert: false);

      await tapAndSave(tester, form);

      expect(told.single.alerts, ['Already taken']);
      expect(told.single.alerted, isFalse);
    });

    testWidgets('checks a field with its validator before writing', (
      tester,
    ) async {
      final (form, told) = await pumpRefused(
        tester,
        validator: (value) => '$value'.endsWith('!') ? 'No bang' : null,
      );

      await tapAndSave(tester, form);

      expect(writes, isEmpty);
      expect(find.text('No bang'), findsOneWidget);
      expect(told.single.error, isA<RecordFormInvalid>());
    });
  });

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
