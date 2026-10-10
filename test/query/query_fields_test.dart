/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

MetadataField _field(
  String name,
  String type, {
  bool searchable = true,
  List<String> operators = const ['='],
  String? target,
}) => metaField(
  name,
  type: type,
  searchable: searchable,
  filterOperators: operators,
  target: target,
);

Map<String, MetadataField> _fields(List<MetadataField> fields) => {
  for (final field in fields) field.name: field,
};

final _metadatas = {
  'household': metaModel(
    'household',
    fields: _fields([
      _field('id', 'integer'),
      _field('name', 'char'),
      _field('cover', 'char', searchable: false),
      _field('search_value', 'fulltext', operators: ['search']),
      _field('initials', 'computed', operators: []),
      _field('owner', 'many2one', target: 'user', operators: ['=', 'any']),
      _field(
        'workspace_users',
        'one2many',
        target: 'household_user',
        operators: ['in'],
      ),
    ]),
  ),
  'household_user': metaModel(
    'household_user',
    fields: _fields([
      _field('user', 'many2one', target: 'user'),
      _field('role', 'choice'),
    ]),
  ),
  'user': metaModel(
    'user',
    fields: _fields([
      _field('id', 'integer', operators: ['=', '<', 'between']),
      _field('email', 'email'),
    ]),
  ),
};

List<String> _names(List<MetadataField> fields) => [
  for (final field in fields) field.name,
];

void main() {
  final household = _metadatas['household']!;

  group('the fields a filter is built on', () {
    test('leaves out the technical ones, the unfiltered ones and the excluded paths', () {
      expect(_names(filterableFields(household)), [
        'name',
        'owner',
        'workspace_users',
      ]);
      expect(_names(filterableFields(household, exclude: ['owner'])), [
        'name',
        'workspace_users',
      ]);
      expect(
        filterableFields(
          _metadatas['user'],
          exclude: ['owner.email'],
          prefix: 'owner',
        ),
        isEmpty,
      );
      expect(filterableFields(null), isEmpty);
    });

    test('walks a path through the relations, a relation and its key being one field', () {
      final members = resolveFieldPath(
        _metadatas,
        'household',
        'workspace_users.user.email',
      )!;

      expect(members.path, 'workspace_users.user.email');
      expect(members.chain.map((link) => link.model), [
        'household',
        'household_user',
        'user',
      ]);
      expect(members.field.type, 'email');
      expect(members.model, 'user');
      expect(members.target, isNull);

      final owner = resolveFieldPath(_metadatas, 'household', 'owner.id')!;

      expect(owner.path, 'owner');
      expect(owner.target, 'user');
      expect(resolveFieldPath(_metadatas, 'household', 'owner.nope'), isNull);
      expect(resolveFieldPath(_metadatas, 'household', ''), isNull);
      expect(resolveFieldPath(null, 'household', 'name'), isNull);
    });

    test('offers on a relation the operators of its key', () {
      final fields = household.fields;

      expect(fieldOperators(_metadatas, fields['owner']), [
        '=',
        'any',
        '<',
        'between',
      ]);
      expect(fieldOperators(_metadatas, fields['name']), ['=']);
      expect(relationKindOf(fields['workspace_users']), FieldKind.multiple);
      expect(relationKindOf(fields['owner']), FieldKind.single);
      expect(relationKindOf(fields['name']), isNull);
    });
  });
}
