/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../metadata/models.dart';
import 'catalog.dart';

const _hiddenFields = {
  'id',
  'search_value',
  'created_by',
  'updated_by',
  'sequence',
};

const _hiddenTypes = {'computed', 'binary', 'point', 'fulltext'};

const _relationKinds = {
  'many2one': FieldKind.single,
  'one2one': FieldKind.single,
  'one_to_one': FieldKind.single,
  'one2many': FieldKind.multiple,
  'many2many': FieldKind.multiple,
};

/// Whether a field leads to one related record ([FieldKind.single]), to
/// several ([FieldKind.multiple]), or is no relation (null). A reference has
/// no single target: it is no relation here.
FieldKind? relationKindOf(MetadataField? field) =>
    field == null ? null : _relationKinds[field.type];

/// The fields a filter can be built on, in the order the metadata gives them.
///
/// A field is offered when the server filters on it and it is not a technical
/// column: `id` is the record itself, and under a relation the relation
/// itself. [prefix] is the path of the level read, for the [exclude]d paths.
List<MetadataField> filterableFields(
  MetadataModel? metadata, {
  List<String> exclude = const [],
  String prefix = '',
}) => [
  for (final field in metadata?.fields.values ?? const <MetadataField>[])
    if (field.searchable &&
        field.filterOperators.isNotEmpty &&
        !_hiddenFields.contains(field.name) &&
        !_hiddenTypes.contains(field.type) &&
        !exclude.contains(
          prefix.isEmpty ? field.name : '$prefix.${field.name}',
        ))
      field,
];

/// A field path walked through the metadata, see [resolveFieldPath].
class ResolvedFieldPath {
  const ResolvedFieldPath({
    required this.path,
    required this.chain,
    required this.field,
    required this.model,
    this.target,
  });

  /// The path as read, `owner` for `owner.id`.
  final String path;

  /// Each field crossed, with the model it belongs to.
  final List<({String model, MetadataField field})> chain;

  /// The last field of the path.
  final MetadataField field;

  /// The model of [field].
  final String model;

  /// The model [field] leads to, for a relation.
  final String? target;
}

/// Walks [path] through the metadata from [model]: each field it crosses, the
/// last one, and the model it reaches. A relation and its key are one field,
/// so `owner.id` resolves as `owner`. Null when a field is unknown.
ResolvedFieldPath? resolveFieldPath(
  Map<String, MetadataModel>? metadatas,
  String model,
  String? path,
) {
  final names = [
    for (final name in (path ?? '').split('.'))
      if (name.isNotEmpty) name,
  ];
  final chain = <({String model, MetadataField field})>[];
  var current = metadatas?[model];

  for (final (index, name) in names.indexed) {
    final field = current?.fields[name];

    if (current == null || field == null) {
      return null;
    }

    chain.add((model: current.name, field: field));

    if (index < names.length - 1) {
      current = metadatas?[field.target];
    }
  }

  if (chain.length > 1 &&
      chain.last.field.name == 'id' &&
      relationKindOf(chain[chain.length - 2].field) != null) {
    chain.removeLast();
  }

  final last = chain.lastOrNull;

  if (last == null) {
    return null;
  }

  return ResolvedFieldPath(
    path: chain.map((link) => link.field.name).join('.'),
    chain: chain,
    field: last.field,
    model: last.model,
    target: last.field.target,
  );
}

/// The operators the server accepts on a field. A relation takes those of
/// its key as well: comparing a relation is comparing the key it holds.
List<String> fieldOperators(
  Map<String, MetadataModel>? metadatas,
  MetadataField? field,
) {
  final own = field?.filterOperators ?? const <String>[];

  if (relationKindOf(field) == null) {
    return own;
  }

  final key = metadatas?[field?.target]?.fields['id']?.filterOperators;

  return {...own, ...?key}.toList();
}
