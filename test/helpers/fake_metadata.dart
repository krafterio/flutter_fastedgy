/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// A [MetadataProvider] serving a fixed map — the seam every metadata-driven
/// test needs, with none of the network.
class FakeMetadataProvider implements MetadataProvider {
  FakeMetadataProvider(this.models, {this.prefix});

  final Map<String, MetadataModel> models;

  @override
  String? prefix;

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => models;

  @override
  Future<MetadataModel?> getMetadata(String name) async => models[name];

  @override
  Future<void> fetchMetadatas() async {}

  @override
  bool get loading => false;

  @override
  dynamic get error => null;

  @override
  String get scope => '';

  @override
  void setPrefix(String? newPrefix) => prefix = newPrefix;
}

MetadataField metaField(
  String name, {
  required String type,
  String? label,
  bool required = false,
  bool readonly = false,
  bool searchable = false,
  String? target,
  List<String>? targets,
  Map<String, String>? choices,
  String? localPlaceholder,
  List<String> filterOperators = const [],
}) => MetadataField(
  name: name,
  label: label ?? name,
  type: type,
  readonly: readonly,
  required: required,
  searchable: searchable,
  extra: false,
  filterOperators: filterOperators,
  target: target,
  targets: targets,
  choices: choices,
  localPlaceholder: localPlaceholder,
);

MetadataModel metaModel(
  String name, {
  required Map<String, MetadataField> fields,
  String? apiName,
  String? label,
  String mode = 'none',
  bool searchable = true,
  String? searchField = 'search_value',
}) => MetadataModel(
  name: name,
  apiName: apiName ?? '${name}s',
  label: label ?? name,
  labelPlural: '${label ?? name}s',
  searchable: searchable,
  searchableFields: searchable ? const ['name'] : const [],
  searchField: searchable ? searchField : null,
  sortable: false,
  synchronizable: mode != 'none',
  synchronizableMode: mode,
  fields: fields,
);

/// The models the grouped-list tests run on, in the shapes the server's
/// metadata endpoint really hands over: a nullable FK targeting its model by
/// metadata name, a `choice` whose keys are enum member names and which reports
/// `required: false` because its column is nullable, and to-many fields no axis
/// can group by.
Map<String, MetadataModel> groupedListMetadata() => {
  'flow': metaModel(
    'flow',
    apiName: 'flows',
    mode: 'partial',
    fields: {
      'id': metaField('id', type: 'integer', readonly: true),
      'reference': metaField(
        'reference',
        type: 'char',
        readonly: true,
        localPlaceholder: 'DRAFT-{seq}',
      ),
      'name': metaField('name', type: 'char', required: true, searchable: true),
      'description': metaField('description', type: 'text'),
      'status': metaField('status', type: 'many2one', target: 'flow_status'),
      'priority': metaField(
        'priority',
        type: 'choice',
        choices: const {
          'low': 'low',
          'normal': 'normal',
          'high': 'high',
          'critical': 'critical',
        },
      ),
      'due_date': metaField('due_date', type: 'date'),
      'project': metaField('project', type: 'many2one', target: 'project'),
      'assignees': metaField('assignees', type: 'many2many', target: 'user'),
      'attachments': metaField(
        'attachments',
        type: 'one2many',
        target: 'attachment',
      ),
    },
  ),
  'flow_status': metaModel(
    'flow_status',
    apiName: 'flow_statuses',
    mode: 'full',
    fields: {
      'id': metaField('id', type: 'integer', readonly: true),
      'name': metaField('name', type: 'char', required: true),
      'sequence': metaField('sequence', type: 'integer'),
      'color': metaField('color', type: 'char'),
    },
  ),
  'project': metaModel(
    'project',
    apiName: 'projects',
    mode: 'full',
    fields: {
      'id': metaField('id', type: 'integer', readonly: true),
      'name': metaField('name', type: 'char', required: true),
      'image': metaField('image', type: 'char'),
    },
  ),
  'user': metaModel(
    'user',
    apiName: 'users',
    mode: 'full',
    fields: {
      'id': metaField('id', type: 'integer', readonly: true),
      'name': metaField('name', type: 'char'),
      'email': metaField('email', type: 'email', required: true),
      'avatar': metaField('avatar', type: 'char'),
      'role': metaField(
        'role',
        type: 'choice',
        readonly: true,
        required: true,
        choices: const {'admin': 'admin', 'user': 'user'},
      ),
    },
  ),
};

FakeMetadataProvider fakeMetadataProvider([
  Map<String, MetadataModel>? models,
]) => FakeMetadataProvider(models ?? groupedListMetadata());
