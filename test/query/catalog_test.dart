/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'query_metadata.dart';

List<String> _ids(List<OperatorOption> options) => [
  for (final option in options) option.id,
];

void main() {
  final fields = queryMetadatas['household']!.fields;

  OperatorOption optionOf(String field, String id) => operatorOptions(
    queryMetadatas,
    fields[field],
  ).firstWhere((option) => option.id == id);

  group('the catalog of operators', () {
    test('sorts the fields by kind', () {
      expect(
        [
          'name',
          'created_at',
          'plan',
          'active',
          'owner',
          'workspace_users',
        ].map((name) => kindOf(fields[name])),
        [
          FieldKind.text,
          FieldKind.datetime,
          FieldKind.choice,
          FieldKind.boolean,
          FieldKind.single,
          FieldKind.multiple,
        ],
      );
      expect(kindOf(metaField('site', type: 'u_r_l')), FieldKind.text);
      expect(kindOf(metaField('to', type: 'reference')), FieldKind.reference);
      expect(
        kindOf(metaField('size', type: 'char', choices: {'s': 'S'})),
        FieldKind.choice,
      );
      expect(
        kindOf(
          metaField('code', type: 'vector', filterOperators: ['icontains']),
        ),
        FieldKind.text,
      );
      expect(kindOf(metaField('blob', type: 'vector')), FieldKind.content);
      expect(kindOf(null), isNull);
    });

    test('offers per kind what the server accepts, never like nor a relation compared with !=', () {
      final name = _ids(operatorOptions(queryMetadatas, fields['name']));

      expect(name, isNot(contains('like')));
      expect(name.first, 'icontains');
      expect(_ids(operatorOptions(queryMetadatas, fields['workspace_users'])), [
        'in',
        'not in',
        'is empty',
        'is not empty',
        'any',
        'not any',
      ]);
      expect(
        _ids(operatorOptions(queryMetadatas, fields['owner'])),
        contains('between'),
      );
      expect(
        _ids(operatorOptions(queryMetadatas, fields['created_at'])).first,
        'on',
      );
    });

    test('reads a range over one local day as « on », or what its ui says', () {
      final options = operatorOptions(queryMetadatas, fields['created_at']);
      const day = '2026-10-08';
      final oneDay = [dayStart(day), dayEnd(day)];
      final twoDays = [dayStart(day), dayEnd('2026-10-09')];

      expect(
        optionOfRule(options, QueryRule('created_at', 'between', oneDay))?.id,
        'on',
      );
      expect(
        optionOfRule(options, QueryRule('created_at', 'between', twoDays))?.id,
        'between',
      );
      expect(
        optionOfRule(
          options,
          QueryRule('created_at', 'between', twoDays)..ui = 'on',
        )?.id,
        'on',
      );
      expect(
        optionOfRule(options, QueryRule('created_at', '=', oneDay)),
        isNull,
      );
    });

    test('keeps a value across operators of the same arity, and turns one into a list of one', () {
      expect(
        convertValue(
          FieldKind.text,
          optionOf('name', 'icontains'),
          optionOf('name', 'starts with'),
          'du',
        ),
        'du',
      );
      expect(
        convertValue(
          FieldKind.text,
          optionOf('name', '='),
          optionOf('name', 'in'),
          'du',
        ),
        ['du'],
      );
      expect(
        convertValue(
          FieldKind.text,
          optionOf('name', 'in'),
          optionOf('name', '='),
          ['du', 'mo'],
        ),
        'du',
      );
      expect(
        convertValue(
          FieldKind.text,
          optionOf('name', '='),
          optionOf('name', 'is empty'),
          'du',
        ),
        isNull,
      );
      expect(
        convertValue(
          FieldKind.datetime,
          optionOf('created_at', 'on'),
          optionOf('created_at', '<'),
          [dayStart('2026-10-08'), dayEnd('2026-10-08')],
        ),
        dayStart('2026-10-08'),
      );
    });

    test('keeps the operator and the value of a rule moving to a field of the same kind', () {
      expect(
        keepOnFieldChange(
          queryMetadatas,
          fields['name'],
          fields['slug']!,
          QueryRule('name', 'starts with', 'du'),
        ),
        (operator: 'starts with', value: 'du', ui: null),
      );
      expect(
        keepOnFieldChange(
          queryMetadatas,
          fields['name'],
          fields['active']!,
          QueryRule('name', '=', 'du'),
        ),
        (operator: 'is true', value: null, ui: null),
      );
      expect(
        keepOnFieldChange(
          queryMetadatas,
          null,
          fields['created_at']!,
          QueryRule(),
        ),
        (operator: 'between', value: null, ui: 'on'),
      );
    });

    test('says every label in each language of the package', () {
      const types = [
        'char',
        'integer',
        'date',
        'datetime',
        'time',
        'boolean',
        'choice',
        'many2one',
        'one2many',
        'reference',
        'json',
      ];
      final labels = {
        for (final type in types)
          for (final option in _offered(type)) option.label,
      };

      expect(labels, hasLength(38));

      for (final language in ['de', 'es', 'fr', 'it']) {
        final words = jsonDecode(
          File('assets/translations/$language.json').readAsStringSync(),
        ) as Map<String, dynamic>;

        expect(
          labels.difference(words.keys.toSet()),
          isEmpty,
          reason: language,
        );
      }
    });
  });
}

/// Every option of the catalog for a type, the field accepting every
/// operator there is.
List<OperatorOption> _offered(String type) => operatorOptions(
  null,
  metaField(
    type,
    type: type,
    filterOperators: const [
      'icontains',
      'not icontains',
      '=',
      '!=',
      'starts with',
      'ends with',
      'in',
      'not in',
      'is empty',
      'is not empty',
      '<',
      '<=',
      '>',
      '>=',
      'between',
      'is true',
      'is false',
      'any',
      'not any',
    ],
  ),
);
