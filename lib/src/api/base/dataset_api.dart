import '../../fetcher/client.dart';
import '../base_model.dart';

/// Request schema for resequencing records within a list while allowing group reassignment.
class ResequenceRequest extends DynamicSchema<ResequenceRequest> {
  ResequenceRequest._(super.data);

  factory ResequenceRequest({
    required String modelName,
    required List<int> ids,
    String? sequenceField,
    int sequenceOffset = 0,
    String? groupField,
    dynamic groupValue,
    Map<String, dynamic>? extra,
  }) {
    final data = <String, dynamic>{
      'model_name': modelName,
      'sequence_offset': sequenceOffset,
      if (sequenceField != null) 'sequence_field': sequenceField,
      if (groupField != null) 'group_field': groupField,
      if (groupValue != null) 'group_value': groupValue,
      'ids': ids,
      if (extra != null) ...extra,
    };
    return ResequenceRequest._(data);
  }

  String get modelName => getString('model_name')!;
  set modelName(String value) => setString('model_name', value);

  String? get sequenceField => getString('sequence_field');
  set sequenceField(String? value) => setString('sequence_field', value);

  int get sequenceOffset => getInt('sequence_offset')!;
  set sequenceOffset(int value) => setInt('sequence_offset', value);

  String? get groupField => getString('group_field');
  set groupField(String? value) => setString('group_field', value);

  dynamic get groupValue => getField('group_value');
  set groupValue(dynamic value) => setField('group_value', value);

  List<int> get ids => getList('ids')!;
  set ids(List<int> value) => setList('ids', value);
}

/// Response schema for resequence operation result
class Resequence<T extends DynamicSchema<T>>
    extends DynamicSchema<Resequence<T>> {
  Resequence(super.data);

  String get modelName => getString('model_name')!;
  set modelName(String value) => setString('model_name', value);

  String? get sequenceField => getString('sequence_field');
  set sequenceField(String? value) => setString('sequence_field', value);

  int get sequenceOffset => getInt('sequence_offset')!;
  set sequenceOffset(int value) => setInt('sequence_offset', value);

  String? get groupField => getString('group_field');
  set groupField(String? value) => setString('group_field', value);

  dynamic get groupValue => getField('group_value');
  set groupValue(dynamic value) => setField('group_value', value);

  List<T> get records => getList('records')!;
  set records(List<T> value) => setList('records', value);
}

/// Dataset API
class DatasetApi<R extends DynamicSchema<R>> {
  final Fetcher _fetcher;

  final String? basePath;

  DatasetApi(this._fetcher, {this.basePath});

  Future<Resequence> resequence(ResequenceRequest request) async {
    final response = await _fetcher.put(
      '${basePath ?? ''}/dataset/resequence',
      request.toJson(),
    );
    return Resequence<R>(response.data);
  }
}
