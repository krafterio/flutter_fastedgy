/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';

import '../helpers/fake_metadata.dart';

const _text = [
  '=',
  '!=',
  'icontains',
  'not icontains',
  'starts with',
  'ends with',
  'in',
  'not in',
  'is empty',
  'is not empty',
  'like',
];
const _number = [
  '=',
  '!=',
  '<',
  '<=',
  '>',
  '>=',
  'between',
  'in',
  'not in',
  'is empty',
  'is not empty',
];
const _dates = [
  '=',
  '!=',
  '<',
  '<=',
  '>',
  '>=',
  'between',
  'is empty',
  'is not empty',
];
const _operators = {
  'char': _text,
  'email': _text,
  'integer': _number,
  'float': _number,
  'date': _dates,
  'datetime': _dates,
  'boolean': ['is true', 'is false'],
  'choice': ['=', '!=', 'in', 'not in', 'is empty', 'is not empty'],
  'many2one': [..._number, 'any', 'not any'],
  'one2many': ['in', 'not in', 'is empty', 'is not empty', 'any', 'not any'],
};

MetadataField _field(
  String name,
  String type, {
  String? label,
  String? target,
  String? inverse,
  Map<String, String>? choices,
}) => metaField(
  name,
  type: type,
  label:
      label ??
      '${name[0].toUpperCase()}${name.substring(1).replaceAll('_', ' ')}',
  searchable: true,
  filterOperators: _operators[type] ?? const [],
  target: target,
  inverse: inverse,
  choices: choices,
);

MetadataModel _model(String name, String label, List<MetadataField> fields) =>
    metaModel(
      name,
      label: label,
      fields: {for (final field in fields) field.name: field},
    );

/// The models of the query builder tests of vue-fastedgy: a household, its
/// members and their users.
final queryMetadatas = {
  'household': _model('household', 'Household', [
    _field('id', 'integer'),
    _field('name', 'char'),
    _field('slug', 'char'),
    _field('created_at', 'datetime', label: 'Created at'),
    _field('plan', 'choice', choices: {'free': 'Free', 'plus': 'Plus'}),
    _field('active', 'boolean'),
    _field('owner', 'many2one', target: 'user', inverse: 'owned_households'),
    _field(
      'workspace_users',
      'one2many',
      label: 'Members',
      target: 'household_user',
      inverse: 'workspace',
    ),
  ]),
  'household_user': _model('household_user', 'Member', [
    _field('role', 'choice', choices: {'admin': 'Admin', 'member': 'Member'}),
    _field('user', 'many2one', target: 'user'),
    _field(
      'workspace',
      'many2one',
      target: 'household',
      inverse: 'workspace_users',
    ),
  ]),
  'user': _model('user', 'User', [
    _field('id', 'integer'),
    _field('name', 'char'),
    _field('email', 'email'),
    _field(
      'owned_households',
      'one2many',
      target: 'household',
      inverse: 'owner',
    ),
  ]),
};
