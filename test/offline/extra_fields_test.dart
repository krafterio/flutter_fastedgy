/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

Map<String, dynamic> _field(String name, String type, {bool extra = false}) => {
  'name': name,
  'label': name,
  'type': type,
  'readonly': false,
  'required': false,
  'searchable': false,
  'extra': extra,
  'filter_operators': <String>[],
  'target': null,
  'targets': null,
  'choices': null,
};

/// A model carrying two workspace extra fields, as the server advertises them:
/// `extra_<name>` entries flagged `extra`, and never the storage column.
final _metadatas = {
  'product': {
    'name': 'product',
    'api_name': 'products',
    'label': 'Product',
    'label_plural': 'Products',
    'searchable': false,
    'sortable': false,
    'sortable_field': null,
    'synchronizable': true,
    'fields': {
      'id': _field('id', 'integer'),
      'name': _field('name', 'char'),
      'extra_priority': _field('extra_priority', 'integer', extra: true),
      'extra_owner': _field('extra_owner', 'char', extra: true),
    },
  },
};

LocalSchema _schema() => LocalSchema.fromModels(
  _metadatas.map((key, value) => MapEntry(key, MetadataModel.fromJson(value))),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSchema extra fields', () {
    test('share one JSON column instead of one column each', () {
      final model = _schema().models['product']!;
      final columns = model.columns.map((field) => field.name).toList();

      expect(columns, contains('extra'));
      expect(columns, isNot(contains('extra_priority')));
      expect(columns, isNot(contains('extra_owner')));
      expect(model.extraFields, {'priority': 'integer', 'owner': 'char'});
    });

    test('resolve a path to its key, and only a declared one', () {
      final model = _schema().models['product']!;

      expect(model.extraFieldName('extra_priority'), 'priority');
      expect(model.extraFieldName('extra_unknown'), isNull);
      expect(model.extraFieldName('name'), isNull);
    });
  });

  group('ReplicaStore extra fields', () {
    late ReplicaStore store;
    late LocalSchema schema;
    late LocalModelSchema model;

    setUp(() async {
      store = ReplicaStore(
        databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
      );
      await store.open();
      schema = _schema();
      model = schema.models['product']!;
      await store.ensureModel(model);
    });

    tearDown(() => store.close());

    test(
      'fold the flat keys into the JSON column, and read them back',
      () async {
        await store.applyDelta(model, 'acme', [
          {'id': 1, 'name': 'Alpha', 'extra_priority': 2, 'extra_owner': 'ada'},
        ], const []);

        // The record is served from `_raw`, so it comes back exactly as the
        // server sent it — flat keys included.
        expect(await store.getById('product', 'acme', 1), {
          'id': 1,
          'name': 'Alpha',
          'extra_priority': 2,
          'extra_owner': 'ada',
        });

        final rows = await store.query(
          schema,
          'product',
          scope: 'acme',
          filter: const ['extra_priority', '=', 2],
        );

        expect(rows.records.map((record) => record['id']), [1]);
      },
    );

    test('a record without extra values stores no key', () async {
      await store.applyDelta(model, 'acme', [
        {'id': 1, 'name': 'Alpha'},
      ], const []);

      final rows = await store.query(
        schema,
        'product',
        scope: 'acme',
        filter: const ['extra_owner', 'is empty'],
      );

      expect(rows.records.map((record) => record['id']), [1]);
    });

    test(
      'the table survives a workspace declaring other extra fields',
      () async {
        await store.applyDelta(model, 'acme', [
          {'id': 1, 'name': 'Alpha', 'extra_priority': 2},
        ], const []);

        // Another workspace: a different extra field set on the same model. The
        // shared JSON column means no schema drift, so nothing is rebuilt and
        // the first workspace keeps its rows.
        final other = LocalModelSchema(
          name: model.name,
          apiName: model.apiName,
          fields: model.fields,
          extraFields: const {'deadline': 'date'},
        );

        final migration = await store.ensureModel(other);

        expect(migration.needsSync, isFalse);
        expect(await store.getById('product', 'acme', 1), isNotNull);
      },
    );
  });
}
