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

    final stored = <String, Object?>{'id': 1, 'name': 'Lamp', 'mail': 'a@b.c'};

    thing = ApiRecord<_Thing>(
      _ThingApi(
        fetcher: createMockFetcher(
          (request) async => MockResponse.json(stored),
          enableAuth: false,
          enableTimezone: false,
          enableRefreshToken: false,
        ),
      ),
    );
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
    container.registerSingleton<RecordFormInputs>(RecordFormInputs());

    await pumpForm(tester, const [RecordFormField('name')]);

    expect(find.byType(Text), findsNothing);
  });

  testWidgets(
    'draws a field with the input of its type, else of its kind, and writes it back',
    (tester) async {
      container.registerSingleton<RecordFormInputs>(
        RecordFormInputs()
          ..register(FieldKind.text, input)
          ..registerType(
            'email',
            (context, input) => Text('mail ${input.value}'),
          ),
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
}
