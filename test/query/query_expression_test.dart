/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the expression corpus shared with vue-fastedgy and fastedgy', () {
    final corpus = jsonDecode(
      File('test/fixtures/expressions.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    for (final entry in corpus['cases'] as List<dynamic>) {
      final {'name': name, 'input': input, 'output': output} =
          entry as Map<String, dynamic>;

      test('writes back $name, and reads its own writing alike', () {
        expect(serializeExpression(parseExpression(input)), output);
        expect(serializeExpression(parseExpression(output)), output);
      });
    }
  });

  group('reading an expression', () {
    test('reads the flat form of a single rule as a group of one', () {
      final tree = parseExpression([
        '|',
        ['name', '=', 'Novel'],
      ]);

      expect(tree.joint, '|');
      expect(tree.children.single, isA<QueryRule>());
    });

    test('reads a block, and keeps what it cannot read as written', () {
      final tree = parseExpression([
        '&',
        [
          ['tags', 'not any', null],
          ['secret', 'like', '%x%', 'extra'],
        ],
      ]);
      final block = tree.children.first as QueryAnyBlock;

      expect(block.negated, isTrue);
      expect(block.group.children, isEmpty);
      expect((tree.children.last as QueryOpaque).raw, [
        'secret',
        'like',
        '%x%',
        'extra',
      ]);
    });

    test('finds a node and its parent, none for the group of a block', () {
      final tree = parseExpression([
        'tags',
        'any',
        ['name', '=', 'a'],
      ]);
      final block = tree.children.single as QueryAnyBlock;

      expect(findQueryNode(tree, block.id)?.parent, same(tree));
      expect(findQueryNode(tree, block.group.id)?.parent, isNull);
      expect(
        findQueryNode(tree, block.group.children.single.id)?.parent,
        same(block.group),
      );
      expect(findQueryNode(tree, -1), isNull);
    });
  });

  group('writing a tree', () {
    test('leaves out what is incomplete, and the groups it empties', () {
      final tree = QueryGroup('&', [
        QueryRule('name', 'icontains', ''),
        QueryRule('', 'in', [1]),
        QueryRule('price', 'between', [10, null]),
        QueryRule('quantity', 'in', []),
        QueryRule('rate', '=', double.nan),
        QueryGroup('|', [QueryRule('name')]),
        QueryRule('rating', 'is empty'),
      ]);

      expect(serializeExpression(tree), ['rating', 'is empty']);
      expect(countConditions(tree), 1);
    });

    test('writes a list for in, and the keys of the related records', () {
      final tree = QueryGroup('&', [
        QueryRule('category', 'in', {'id': 2}),
        QueryRule('owner', '=', {'id': 7}),
      ]);

      expect(serializeExpression(tree), [
        '&',
        [
          [
            'category',
            'in',
            [2],
          ],
          ['owner', '=', 7],
        ],
      ]);
    });

    test(
      'counts a block once whatever it holds, and a rule it cannot read',
      () {
        final tree = parseExpression([
          '&',
          [
            [
              'tags',
              'any',
              [
                '|',
                [
                  ['name', '=', 'a'],
                  ['name', '=', 'b'],
                ],
              ],
            ],
            ['secret', 'like', '%x%', 'extra'],
          ],
        ]);

        expect(countConditions(tree), 2);
      },
    );

    test('says two expressions are the same when they read alike', () {
      expect(
        sameExpression(
          [
            '|',
            ['a', '=', 1],
            ['b', '=', 2],
          ],
          [
            '|',
            [
              ['a', '=', 1],
              ['b', '=', 2],
            ],
          ],
        ),
        isTrue,
      );
      expect(
        sameExpression(
          [
            ['a', '=', 1],
          ],
          ['a', '=', 1],
        ),
        isTrue,
      );
      expect(sameExpression(['a', '=', 1], ['a', '=', 2]), isFalse);
      expect(sameExpression(['a', '=', 1], ['a', '=', 1.0]), isTrue);
      expect(sameExpression(null, []), isTrue);
    });

    test('knows how many values an operator takes', () {
      expect(['is empty', '=', 'between', 'not in', 'not any'].map(arityOf), [
        Arity.none,
        Arity.one,
        Arity.two,
        Arity.list,
        Arity.sub,
      ]);
    });
  });

  group('QueryExpression', () {
    test('edits the tree and writes the expression it says', () {
      final query = QueryExpression();
      final root = query.tree.id;
      var told = 0;

      query.addListener(() => told++);

      final rule = query.addRule(
        root,
        field: 'name',
        operator: 'icontains',
        value: 'lap',
      )!;
      final group = query.addGroup(root, joint: '|')!;
      query.addRule(group, field: 'quantity', operator: '>', value: 3);
      query.addRule(group, field: 'is_active', operator: 'is true');

      expect(query.expression, [
        '&',
        [
          ['name', 'icontains', 'lap'],
          [
            '|',
            [
              ['quantity', '>', 3],
              ['is_active', 'is true'],
            ],
          ],
        ],
      ]);
      expect(query.count, 3);

      query.setJoint(root, '|');
      query.remove(group);
      query.replace(rule, QueryAnyBlock('tags'));

      expect(query.expression, ['tags', 'any', null]);
      expect(told, 7);
      expect(query.addRule(rule), isNull);
    });

    test(
      'changes a rule, its value set to null, its ui cleared by a new operator',
      () {
        final query = QueryExpression([
          'created_at',
          'between',
          ['2026-10-07T22:00:00.000Z', '2026-10-08T21:59:59.999Z'],
        ]);
        final rule = query.tree.children.single as QueryRule;

        query.update(rule.id, ui: 'on');
        query.update(rule.id, value: null);

        expect(rule.ui, 'on');
        expect(rule.value, isNull);

        query.update(rule.id, operator: '<');

        expect(rule.operator, '<');
        expect(rule.ui, isNull);

        query.update(rule.id, operator: 'between', ui: 'on');

        expect(rule.ui, 'on');
      },
    );

    test('switches a block between at least one and none', () {
      final query = QueryExpression(['tags', 'any', null]);
      final block = query.tree.children.single as QueryAnyBlock;

      query.update(block.id, negated: true);

      expect(query.expression, ['tags', 'not any', null]);
    });

    test('keeps the row being typed when its own expression comes back, and reads a new one', () {
      final source = ValueNotifier<Object?>(['name', '=', 'Novel']);
      final query = QueryExpression(source);

      query.addRule(query.tree.id);
      source.value = query.expression;

      expect(query.tree.children, hasLength(2));

      source.value = ['quantity', '>', 0];

      expect(query.tree.children.map((node) => (node as QueryRule).field), [
        'quantity',
      ]);

      query.dispose();
      source.value = ['name', '=', 'Novel'];

      expect(query.tree.children, hasLength(1));
    });

    test('clears and loads', () {
      final query = QueryExpression(['a', '=', 1]);

      query.clear();
      expect(query.expression, isNull);

      query.load([
        '|',
        [
          ['a', '=', 1],
          ['b', '=', 2],
        ],
      ]);
      expect(query.count, 2);
    });
  });
}
