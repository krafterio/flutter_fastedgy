/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  group('parseFtsSearch', () {
    test('single bare word becomes an optional prefix match', () {
      final query = parseFtsSearch('projet');

      expect(query.positive, '"projet" *');
      expect(query.excluded, isNull);
    });

    test('bare words are OR combined', () {
      final query = parseFtsSearch('projet alpha');

      expect(query.positive, '("projet" * OR "alpha" *)');
      expect(query.excluded, isNull);
    });

    test('+word is mandatory alongside bare words', () {
      final query = parseFtsSearch('projet +alpha');

      expect(query.positive, '"projet" * AND "alpha" *');
    });

    test('-word is excluded', () {
      final query = parseFtsSearch('projet -alpha -beta');

      expect(query.positive, '"projet" *');
      expect(query.excluded, '"alpha" * OR "beta" *');
    });

    test('only excluded words leave no positive query', () {
      final query = parseFtsSearch('-alpha');

      expect(query.positive, isNull);
      expect(query.excluded, '"alpha" *');
    });

    test('quoted phrases match exactly without prefix', () {
      final query = parseFtsSearch('"projet alpha" beta');

      expect(query.positive, '"beta" * AND "projet alpha"');
    });

    test('unicode quotes are normalized', () {
      expect(parseFtsSearch('«projet alpha»').positive, '"projet alpha"');
      expect(parseFtsSearch('“projet alpha”').positive, '"projet alpha"');
    });

    test('punctuation splits into words', () {
      final query = parseFtsSearch('ada@x.io');

      expect(query.positive, '("ada" * OR "x" * OR "io" *)');
    });

    test('ligatures are folded like unaccent', () {
      expect(parseFtsSearch('cœur').positive, '"coeur" *');
    });

    test('empty or symbol-only input yields an empty query', () {
      expect(parseFtsSearch('').isEmpty, isTrue);
      expect(parseFtsSearch('  @!% ').isEmpty, isTrue);
      expect(parseFtsSearch('"+"').isEmpty, isTrue);
    });
  });

  group('searchWeightForType', () {
    test('mirrors the server SEARCH_WEIGHT_FIELD_MAP', () {
      expect(searchWeightForType('char'), 'a');
      expect(searchWeightForType('text'), 'b');
      expect(searchWeightForType('html'), 'c');
      expect(searchWeightForType('h_t_m_l'), 'c');
      expect(searchWeightForType('phone'), 'd');
      expect(searchWeightForType('email'), 'd');
      expect(searchWeightForType('unknown'), 'd');
    });
  });

  group('computeSearchValues', () {
    const model = LocalModelSchema(
      name: 'task',
      apiName: 'tasks',
      fields: {
        'id': LocalFieldSchema(name: 'id', type: 'integer'),
        'name': LocalFieldSchema(name: 'name', type: 'char'),
        'summary': LocalFieldSchema(name: 'summary', type: 'char'),
        'description': LocalFieldSchema(name: 'description', type: 'text'),
        'email': LocalFieldSchema(name: 'email', type: 'email'),
      },
      searchField: 'search_value',
      searchWeights: {
        'name': 'a',
        'summary': 'a',
        'description': 'b',
        'email': 'd',
      },
    );

    test('groups sources by weight and folds ligatures', () {
      final values = computeSearchValues(model, {
        'name': 'Cœur de projet',
        'summary': 'Alpha',
        'description': 'Notes',
        'email': 'ada@x.io',
      });

      expect(values['search_value_fts_a'], 'Coeur de projet Alpha');
      expect(values['search_value_fts_b'], 'Notes');
      expect(values['search_value_fts_c'], '');
      expect(values['search_value_fts_d'], 'ada@x.io');
    });

    test('skips null, map and list values', () {
      final values = computeSearchValues(model, {
        'name': null,
        'summary': {'fr': 'Bonjour'},
        'description': ['a'],
        'email': 42,
      });

      expect(values['search_value_fts_a'], '');
      expect(values['search_value_fts_b'], '');
      expect(values['search_value_fts_d'], '42');
    });
  });

  group('LocalModelSchema search config', () {
    test('searchable requires a search field and sources', () {
      const bare = LocalModelSchema(name: 'x', apiName: 'xs', fields: {});

      expect(bare.searchable, isFalse);
      expect(bare.searchFingerprint, '');

      const noSources = LocalModelSchema(
        name: 'x',
        apiName: 'xs',
        fields: {},
        searchField: 'search_value',
      );

      expect(noSources.searchable, isFalse);
    });

    test('fingerprint follows the sources and weights', () {
      const one = LocalModelSchema(
        name: 'x',
        apiName: 'xs',
        fields: {},
        searchField: 'search_value',
        searchWeights: {'name': 'a'},
      );
      const two = LocalModelSchema(
        name: 'x',
        apiName: 'xs',
        fields: {},
        searchField: 'search_value',
        searchWeights: {'name': 'a', 'description': 'b'},
      );

      expect(one.searchFingerprint, isNot(two.searchFingerprint));
    });
  });

  group('LocalSchema.fromModels', () {
    test('derives the search config from the metadata', () {
      final metadata = MetadataModel.fromJson({
        'name': 'task',
        'api_name': 'tasks',
        'label': 'Task',
        'label_plural': 'Tasks',
        'searchable': true,
        'searchable_fields': ['name', 'description', 'missing'],
        'search_field': 'search_value',
        'sortable': false,
        'sortable_field': null,
        'fields': {
          'id': _fieldJson('id', 'integer'),
          'name': _fieldJson('name', 'char'),
          'description': _fieldJson('description', 'text'),
          'search_value': _fieldJson('search_value', 'fulltext'),
        },
      });
      final schema = LocalSchema.fromModels({'task': metadata});
      final model = schema.models['task']!;

      expect(model.searchable, isTrue);
      expect(model.searchField, 'search_value');
      expect(model.searchWeights, {'name': 'a', 'description': 'b'});
      // Exposed in the metadata (filterable) but never a physical column.
      expect(model.columns.map((c) => c.name), isNot(contains('search_value')));
    });
  });
}

Map<String, dynamic> _fieldJson(String name, String type) => {
  'name': name,
  'label': name,
  'type': type,
  'readonly': false,
  'required': false,
  'searchable': false,
  'extra': false,
  'filter_operators': <String>[],
};
