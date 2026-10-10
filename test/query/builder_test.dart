/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

import 'query_metadata.dart';

List<String> _labels(List<FieldEntry> entries) => [
  for (final entry in entries) entry.label,
];

void main() {
  final fields = queryMetadatas['household']!.fields;

  group('the field picker', () {
    test('walks into a relation, never offering the way back through it', () {
      final picker = FieldPicker(metadatas: queryMetadatas, model: 'household');

      expect(_labels(picker.entries), [
        'Active',
        'Created at',
        'Members',
        'Name',
        'Owner',
        'Plan',
        'Slug',
      ]);
      expect(
        picker.entries.where((entry) => entry.relation).map((e) => e.path),
        ['workspace_users', 'owner'],
      );

      picker.enter(picker.entries.firstWhere((e) => e.label == 'Owner'));

      expect(picker.crumbs, ['Household', 'Owner']);
      expect(_labels(picker.entries), ['Email', 'Name']);
      expect(picker.entries.first.path, 'owner.email');

      picker.back();
      picker.enter(picker.entries.firstWhere((e) => e.label == 'Members'));

      expect(_labels(picker.entries), ['Role', 'User']);
    });

    test(
      'nor the way back through the relation of the block a condition sits in',
      () {
        final picker = FieldPicker(
          metadatas: queryMetadatas,
          model: 'household',
          path: 'workspace_users',
        );

        expect(picker.crumbs, ['Member']);
        expect(_labels(picker.entries), ['Role', 'User']);
        expect(picker.entries.last.path, 'user');
      },
    );

    test(
      'finds a deeper field from the top when asked to, without entering',
      () {
        final picker = FieldPicker(
          metadatas: queryMetadatas,
          model: 'household',
          deepFieldSearch: true,
        )..search = 'MAIL';

        expect(_labels(picker.entries), ['Owner › Email']);
        expect(picker.entries.single.path, 'owner.email');
        expect(picker.entries.single.relation, isFalse);

        picker.search = 'CRÉA';

        expect(_labels(picker.entries), ['Created at']);
        expect(
          _labels(
            (FieldPicker(
              metadatas: queryMetadatas,
              model: 'household',
            )..search = 'mail').entries,
          ),
          isEmpty,
        );
      },
    );

    test('puts the field chosen on the rule, keeping what can be kept', () {
      final query = QueryExpression(['name', 'starts with', 'du']);
      final rule = query.tree.children.single as QueryRule;
      final picker = FieldPicker(
        metadatas: queryMetadatas,
        model: 'household',
        deepFieldSearch: true,
      )..search = 'email';

      picker.choose(query, rule, picker.entries.single);

      expect(query.expression, ['owner.email', 'starts with', 'du']);

      picker.search = 'created';
      picker.choose(query, rule, picker.entries.single);

      expect(rule.field, 'created_at');
      expect(rule.operator, 'between');
      expect(rule.ui, 'on');
      expect(rule.value, isNull);
    });
  });

  group('a condition', () {
    test(
      'shows as written what the metadata do not describe, once they are there',
      () {
        bool readOnly(List<Object?> expression, {bool known = true}) =>
            isReadOnlyRule(
              known ? queryMetadatas : null,
              'household',
              parseExpression(expression).children.single,
            );

        expect(readOnly(['name', 'like', '%a%']), isTrue);
        expect(readOnly(['nope', '=', 1]), isTrue);
        expect(readOnly(['name', '=', 1, 'extra']), isTrue);
        expect(readOnly(['name', '=', 'a']), isFalse);
        expect(readOnly(['nope', '=', 1], known: false), isFalse);
        expect(
          isReadOnlyRule(queryMetadatas, 'household', QueryRule()),
          isFalse,
        );
      },
    );

    test('takes a value once an operator that takes one is chosen', () {
      final options = operatorOptions(queryMetadatas, fields['owner']);
      OperatorOption option(String id) =>
          options.firstWhere((option) => option.id == id);

      expect(hasValue(option('=')), isTrue);
      expect(hasValue(option('is empty')), isFalse);
      expect(hasValue(option('any')), isFalse);
      expect(hasValue(null), isFalse);
    });
  });

  group('a block on a relation', () {
    test('switches between at least one and none, and folds back into a row once confirmed', () {
      final query = QueryExpression([
        'workspace_users',
        'any',
        ['role', '=', 'admin'],
      ]);
      final block = query.tree.children.single as QueryAnyBlock;
      final options = operatorOptions(
        queryMetadatas,
        fields['workspace_users'],
      );
      OperatorOption option(String id) =>
          options.firstWhere((option) => option.id == id);

      expect(foldAnyBlock(query, block, option('not any')), isTrue);
      expect(block.negated, isTrue);

      expect(foldAnyBlock(query, block, option('in')), isFalse);
      expect(query.tree.children.single, same(block));

      expect(foldAnyBlock(query, block, option('in'), confirmed: true), isTrue);

      final rule = query.tree.children.single as QueryRule;

      expect((rule.field, rule.operator), ('workspace_users', 'in'));
    });

    test('is titled by its relation and what it asks of it', () {
      ({String key, String relation}) title(
        String field, {
        bool negated = false,
      }) => anyBlockTitle(
        queryMetadatas,
        'household',
        QueryAnyBlock(field, negated: negated),
      );

      expect(title('owner'), (key: '{relation}: matching…', relation: 'Owner'));
      expect(title('workspace_users', negated: true), (
        key: '{relation}: none that…',
        relation: 'Members',
      ));
      expect(title('workspace_users.user'), (
        key: '{relation}: matching…',
        relation: 'Members › User',
      ));
      expect(title('nope').relation, 'nope');

      final keys = {
        for (final field in ['owner', 'workspace_users'])
          for (final negated in [true, false])
            title(field, negated: negated).key,
      };

      for (final language in ['de', 'es', 'fr', 'it']) {
        final words = jsonDecode(
          File('assets/translations/$language.json').readAsStringSync(),
        ) as Map<String, dynamic>;

        expect(keys.difference(words.keys.toSet()), isEmpty, reason: language);
      }
    });
  });

  group('the inputs of a value', () {
    test('compare texts without their case nor their accents', () {
      expect(foldText('Échéance CRÉÉE'), 'echeance creee');
      expect(foldText('Eté'), 'ete');
      expect(foldText(null), '');
    });

    test('read numbers, lists, ranges and references', () {
      expect(readNumber(' 12 '), 12);
      expect(readNumber('1.5'), 1.5);
      expect(readNumber(''), isNull);
      expect(readNumber('nope'), isNull);
      expect(readNumber('Infinity'), isNull);
      expect(parseListInput(['1', '2', 'x', ''], FieldKind.number), [1, 2]);
      expect(parseListInput([' a ', '', 'b'], FieldKind.text), ['a', 'b']);
      expect(rangeValue(['10', ''], FieldKind.number), [10, null]);
      expect(rangeValue(['2026-10-01', ''], FieldKind.date), [
        '2026-10-01',
        null,
      ]);
      expect(referenceValue('user', 3, multiple: false), ['user', 3]);
      expect(referenceValue('user', null, multiple: false), isNull);
      expect(referenceValue('user', [1, 2], multiple: true), [
        ['user', 1],
        ['user', 2],
      ]);
      expect(referenceValue('user', null, multiple: true), isEmpty);
    });
  });
}
