import '../../fetcher/client.dart';

/// Request schema for resequencing records within a list while allowing group reassignment.
class ResequenceRequest {
  final String modelName;

  final String? sequenceField;

  final int sequenceOffset;

  final String? groupField;

  final dynamic groupValue;

  final List<int> ids;

  const ResequenceRequest({
    required this.modelName,
    required this.ids,
    this.sequenceField,
    this.sequenceOffset = 0,
    this.groupField,
    this.groupValue,
  });

  factory ResequenceRequest.fromJson(Map<String, dynamic> json) => ResequenceRequest(
        modelName: json['model_name'] as String,
        sequenceField: json['sequence_field'] as String?,
        sequenceOffset: json['sequence_offset'] as int? ?? 0,
        groupField: json['group_field'] as String?,
        groupValue: json['group_value'],
        ids: (json['ids'] as List<dynamic>).map((e) => e as int).toList(),
      );

  Map<String, dynamic> toJson() => {
        'model_name': modelName,
        'sequence_field': sequenceField,
        'sequence_offset': sequenceOffset,
        'group_field': groupField,
        'group_value': groupValue,
        'ids': ids,
      };
}

/// Response schema for resequence operation result
class Resequence {
  final String modelName;

  final String? sequenceField;

  final int sequenceOffset;

  final String? groupField;

  final dynamic groupValue;

  final List<Map<String, dynamic>> records;

  const Resequence({
    required this.modelName,
    required this.records,
    this.sequenceField,
    this.sequenceOffset = 0,
    this.groupField,
    this.groupValue,
  });

  factory Resequence.fromJson(Map<String, dynamic> json) => Resequence(
        modelName: json['model_name'] as String,
        sequenceField: json['sequence_field'] as String?,
        sequenceOffset: json['sequence_offset'] as int? ?? 0,
        groupField: json['group_field'] as String?,
        groupValue: json['group_value'],
        records: (json['records'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'model_name': modelName,
        'sequence_field': sequenceField,
        'sequence_offset': sequenceOffset,
        'group_field': groupField,
        'group_value': groupValue,
        'records': records,
      };
}

/// Dataset API
class DatasetApi {
  final Fetcher _fetcher;

  final String? basePath;

  DatasetApi(this._fetcher, {this.basePath});

  Future<Resequence> resequence(ResequenceRequest request) async {
    final response = await _fetcher.put('${basePath ?? ''}/dataset/resequence', request);
    return Resequence.fromJson(response.data as Map<String, dynamic>);
  }
}
