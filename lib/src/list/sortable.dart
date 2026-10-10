/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_model.dart';
import '../api/base/dataset_api.dart';
import '../logging/logger.dart';
import '../metadata/models.dart';

final _log = getLogger('Sortable');

/// Where an api model answers: its prefix (`/{workspace}`, `/console`), its
/// path without the last segment when it names no model.
String apiPrefixOf(ApiModel api) {
  if (api.modelName != null) {
    return api.basePath;
  }

  final cut = api.basePath.lastIndexOf('/');

  return cut <= 0 ? '' : api.basePath.substring(0, cut);
}

/// The manual order of a list, the port of `useSortable`: sortable by hand
/// when the metadata of the model say so ([sortable] null), always when
/// [sortable] is true, never when it is false. Forced on metadata that do not
/// read, the order is kept in `sequence`.
class Sortable {
  Sortable(this.api, {this.sortable, String? datasetPrefix})
    : _prefix = datasetPrefix ?? apiPrefixOf(api);

  final ApiModel api;
  final bool? sortable;

  /// Where the `/dataset` routes answer: the prefix of the model unless said
  /// otherwise, `''` for the root.
  final String _prefix;

  bool _isSortable = false;
  String? _sortableField;

  bool get isSortable => _isSortable;

  String? get sortableField => _sortableField;

  String? getSortableField() => _sortableField;

  /// Completes once the metadata of the model are read.
  late final Future<void> ready = readMetadata();

  /// Reads the metadata again, another workspace's for instance.
  Future<void> readMetadata() async {
    MetadataModel? model;

    try {
      model = await api.metadata();
    } catch (_) {
      model = null;
    }

    final field = (model?.sortableField?.isNotEmpty ?? false)
        ? model!.sortableField
        : 'sequence';
    final on = sortable ?? (model?.sortable ?? false);

    _isSortable = on;
    _sortableField = on ? field : null;
  }

  /// Saves the order of [ids], the first of them at [sequenceOffset] in the
  /// whole list, moved to the group [groupValue] of [groupField] when given.
  Future<void> resequence(
    List<int> ids, {
    int sequenceOffset = 0,
    String? groupField,
    Object? groupValue,
  }) async {
    final field = _sortableField;

    if (!_isSortable || field == null) {
      _log.warning('Resequencing is not enabled');

      return;
    }

    final model = await api.resolveModelName();

    if (model == null) {
      throw StateError('The model of ${api.basePath} is unknown');
    }

    await DatasetApi<GenericBaseModel>(
      api.fetcher,
      basePath: _prefix,
    ).resequence(
      ResequenceRequest(
        modelName: model,
        ids: ids,
        sequenceField: field,
        sequenceOffset: sequenceOffset,
        groupField: groupField,
        groupValue: groupValue,
      ),
    );
  }
}
