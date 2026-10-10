/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'query_metadata.dart';

/// The inputs vue-fastedgy-query-builder gives, in its order.
const FilterInputs<String> _package = [
  (FilterInputMatch(kinds: [FieldKind.text]), 'TextInput'),
  (FilterInputMatch(kinds: [FieldKind.number]), 'NumberInput'),
  (FilterInputMatch(kinds: [FieldKind.date]), 'DateInput'),
  (FilterInputMatch(kinds: [FieldKind.time]), 'TimeInput'),
  (FilterInputMatch(kinds: [FieldKind.datetime]), 'DateTimeInput'),
  (FilterInputMatch(kinds: [FieldKind.choice]), 'ChoiceInput'),
  (
    FilterInputMatch(kinds: [FieldKind.single, FieldKind.multiple]),
    'RelationInput',
  ),
  (FilterInputMatch(kinds: [FieldKind.reference]), 'ReferenceInput'),
  (
    FilterInputMatch(
      kinds: [FieldKind.text, FieldKind.number],
      arity: Arity.list,
    ),
    'ListInput',
  ),
  (
    FilterInputMatch(
      kinds: [FieldKind.number, FieldKind.date, FieldKind.time],
      arity: Arity.two,
    ),
    'RangeInput',
  ),
  (
    FilterInputMatch(kinds: [FieldKind.datetime], arity: Arity.two),
    'DateTimeInput',
  ),
  (
    FilterInputMatch(kinds: [FieldKind.choice], arity: Arity.list),
    'ChoiceInput',
  ),
  (
    FilterInputMatch(
      kinds: [FieldKind.single, FieldKind.multiple],
      arity: Arity.list,
    ),
    'RelationInput',
  ),
  (
    FilterInputMatch(kinds: [FieldKind.reference], arity: Arity.list),
    'ReferenceInput',
  ),
  (
    FilterInputMatch(
      kinds: [FieldKind.single],
      operators: ['<', '<=', '>', '>='],
    ),
    'NumberInput',
  ),
  (
    FilterInputMatch(kinds: [FieldKind.single], operators: ['between']),
    'RangeInput',
  ),
];

FilterInputRule _rule(FieldKind kind, String operator, {String? type}) => (
  type: type ?? kind.name,
  kind: kind,
  operator: operator,
  arity: arityOf(operator),
);

void main() {
  group('the registry of inputs', () {
    test(
      'gives each rule the input matching the most of what an entry declares',
      () {
        String? input(FieldKind kind, String operator) =>
            resolveFilterInput(_rule(kind, operator), _package);

        expect(input(FieldKind.text, 'icontains'), 'TextInput');
        expect(input(FieldKind.choice, '='), 'ChoiceInput');
        expect(input(FieldKind.text, 'in'), 'ListInput');
        expect(input(FieldKind.number, 'between'), 'RangeInput');
        expect(input(FieldKind.single, '='), 'RelationInput');
        expect(input(FieldKind.single, 'in'), 'RelationInput');
        expect(input(FieldKind.single, '<'), 'NumberInput');
        expect(input(FieldKind.single, 'between'), 'RangeInput');
        expect(input(FieldKind.date, '='), 'DateInput');
        expect(input(FieldKind.date, 'between'), 'RangeInput');
        expect(input(FieldKind.content, 'is empty'), isNull);
      },
    );

    test('lets one list replace an input for itself alone, and an application for all', () {
      final date = _rule(FieldKind.date, '=');
      final application = [
        ..._package,
        (
          const FilterInputMatch(types: ['date'], arity: Arity.one),
          'ProjectDate',
        ),
      ];

      expect(
        resolveFilterInput(
          date,
          _package,
          local: [
            (const FilterInputMatch(types: ['date']), 'ListDate'),
          ],
        ),
        'ListDate',
      );
      expect(resolveFilterInput(date, application), 'ProjectDate');
      expect(
        resolveFilterInput(_rule(FieldKind.date, 'between'), application),
        'RangeInput',
      );
    });
  });

  group('the sources of the values of a relation', () {
    test('list a model through its own API, named by the first field that names a record', () {
      final source = defaultValueSource(
        'user',
        prefix: '/{workspace}',
        metadatas: queryMetadatas,
      );
      final reader = source.reader as GenericApiModel;

      expect(reader.basePath, '/{workspace}');
      expect(reader.modelName, 'user');
      expect(source.fields, ['name', 'email']);
      expect(source.label!({'id': 3, 'name': 'Ana'}), 'Ana');
      expect(source.label!({'id': 3, 'name': ''}), '#3');
      expect(source.subtitle!({'email': 'ana@krafter.io'}), 'ana@krafter.io');
      expect(source.image, isNull);
      expect(source.searchFilter!('ana'), [
        '|',
        [
          ['name', 'icontains', 'ana'],
          ['email', 'icontains', 'ana'],
        ],
      ]);
    });

    test(
      'search on the fulltext field, or on the key when nothing reads as text',
      () {
        final metadatas = {
          'note': metaModel(
            'note',
            fields: {
              'title': metaField(
                'title',
                type: 'char',
                filterOperators: ['icontains'],
              ),
              'search_value': metaField('search_value', type: 'fulltext'),
              'cover': metaField('cover', type: 'char'),
            },
          ),
          'tag': metaModel(
            'tag',
            fields: {'code': metaField('code', type: 'integer')},
          ),
        };
        final note = defaultValueSource('note', metadatas: metadatas);
        final tag = defaultValueSource('tag', metadatas: metadatas);

        expect(note.fields, ['title', 'cover']);
        expect(note.searchFilter!('idea'), [
          'search_value',
          'search_fuzzy',
          'idea',
        ]);
        expect(tag.searchFilter!('12'), ['id', '=', 12]);
        expect(tag.searchFilter!('red'), ['id', '=', 0]);
      },
    );

    test('take what a list declares over what the application does, over the default', () {
      registerValueSource(
        'household_user',
        (context) =>
            ValueSource(label: (record) => 'member of ${context.prefix}'),
      );

      const context = ValueSourceContext(prefix: '/acme');
      final local = ValueSourceContext(
        prefix: '/acme',
        metadatas: queryMetadatas,
        valueSources: {
          'household_user': (_) => const ValueSource(fields: ['role']),
        },
      );

      expect(
        resolveValueSource('household_user', context).label!({'id': 1}),
        'member of /acme',
      );
      expect(resolveValueSource('household_user', local).fields, ['role']);
      expect(
        resolveValueSource('household_user', local).label!({'id': 1}),
        '#1',
      );
      expect(resolveValueSource('user', local).fields, ['name', 'email']);
    });
  });
}
