/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Represents metadata for a single field in a model
class MetadataField {
  final String name;
  final String label;
  final String type;
  final bool readonly;
  final bool required;
  final bool searchable;
  final bool extra;
  final List<String> filterOperators;
  final String? target;
  final List<String>? targets;
  final Map<String, String>? choices;

  const MetadataField({
    required this.name,
    required this.label,
    required this.type,
    required this.readonly,
    required this.required,
    required this.searchable,
    required this.extra,
    required this.filterOperators,
    this.target,
    this.targets,
    this.choices,
  });

  /// Resolve the human-readable label of a choice value (returns the raw value
  /// when the field has no choices or the value is unknown).
  String choiceLabel(Object? value) {
    if (value == null) return '';
    return choices?[value.toString()] ?? value.toString();
  }

  /// Create a MetadataField from JSON
  factory MetadataField.fromJson(Map<String, dynamic> json) {
    return MetadataField(
      name: json['name'] as String,
      label: json['label'] as String,
      type: json['type'] as String,
      readonly: json['readonly'] as bool,
      required: json['required'] as bool,
      searchable: json['searchable'] as bool,
      extra: json['extra'] as bool,
      filterOperators: (json['filter_operators'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      target: json['target'] as String?,
      targets: (json['targets'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      choices: (json['choices'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value as String),
      ),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'label': label,
      'type': type,
      'readonly': readonly,
      'required': required,
      'searchable': searchable,
      'extra': extra,
      'filter_operators': filterOperators,
      'target': target,
      'targets': targets,
      'choices': choices,
    };
  }
}

/// Represents metadata for a model
class MetadataModel {
  final String name;
  final String apiName;
  final String label;
  final String labelPlural;
  final bool searchable;

  /// Source fields aggregated into the fulltext search field (server-driven).
  final List<String> searchableFields;

  /// Name of the fulltext search field (e.g. `search_value`), when searchable.
  final String? searchField;
  final bool sortable;
  final String? sortableField;

  /// Whether the client may replicate/sync this model offline (server-driven).
  final bool synchronizable;
  final Map<String, MetadataField> fields;

  const MetadataModel({
    required this.name,
    required this.apiName,
    required this.label,
    required this.labelPlural,
    required this.searchable,
    required this.sortable,
    required this.fields,
    this.searchableFields = const [],
    this.searchField,
    this.sortableField,
    this.synchronizable = false,
  });

  /// Create a MetadataModel from JSON
  factory MetadataModel.fromJson(Map<String, dynamic> json) {
    final fieldsJson = json['fields'] as Map<String, dynamic>;
    final fields = fieldsJson.map(
      (key, value) =>
          MapEntry(key, MetadataField.fromJson(value as Map<String, dynamic>)),
    );

    return MetadataModel(
      name: json['name'] as String,
      apiName: json['api_name'] as String,
      label: json['label'] as String,
      labelPlural: json['label_plural'] as String,
      searchable: json['searchable'] as bool,
      searchableFields:
          (json['searchable_fields'] as List?)?.cast<String>() ?? const [],
      searchField: json['search_field'] as String?,
      sortable: json['sortable'] as bool,
      sortableField: json['sortable_field'] as String?,
      synchronizable: json['synchronizable'] as bool? ?? false,
      fields: fields,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'api_name': apiName,
      'label': label,
      'label_plural': labelPlural,
      'searchable': searchable,
      'searchable_fields': searchableFields,
      'search_field': searchField,
      'sortable': sortable,
      'sortable_field': sortableField,
      'synchronizable': synchronizable,
      'fields': fields.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}
