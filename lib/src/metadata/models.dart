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
  });

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
  final bool sortable;
  final String? sortableField;
  final Map<String, MetadataField> fields;

  const MetadataModel({
    required this.name,
    required this.apiName,
    required this.label,
    required this.labelPlural,
    required this.searchable,
    required this.sortable,
    this.sortableField,
    required this.fields,
  });

  /// Create a MetadataModel from JSON
  factory MetadataModel.fromJson(Map<String, dynamic> json) {
    final fieldsJson = json['fields'] as Map<String, dynamic>;
    final fields = fieldsJson.map(
      (key, value) => MapEntry(
        key,
        MetadataField.fromJson(value as Map<String, dynamic>),
      ),
    );

    return MetadataModel(
      name: json['name'] as String,
      apiName: json['api_name'] as String,
      label: json['label'] as String,
      labelPlural: json['label_plural'] as String,
      searchable: json['searchable'] as bool,
      sortable: json['sortable'] as bool,
      sortableField: json['sortable_field'] as String?,
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
      'sortable': sortable,
      'sortable_field': sortableField,
      'fields': fields.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}
