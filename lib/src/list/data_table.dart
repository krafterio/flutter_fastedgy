/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/painting.dart' show TextAlign;

import '../api/base_model.dart';
import '../container/container.dart';
import '../metadata/metadata_provider.dart';
import '../metadata/models.dart';
import '../query/registry.dart';
import 'column_filter.dart';
import 'data_iterator.dart';
import 'sortable.dart';

/// A column of a [DataTable]: the column of vue-fastedgy and melimelo's
/// `SimpleTableColumn` in one.
class DataTableColumn {
  const DataTableColumn(
    this.key, {
    this.label,
    this.width,
    this.flex = 2,
    this.sortable,
    this.sortField,
    this.type,
    this.align,
    this.currency,
    this.filter,
    this.filterable = false,
  }) : meta = null;

  const DataTableColumn._resolved(
    this.key, {
    required this.label,
    required this.width,
    required this.flex,
    required this.sortable,
    required this.sortField,
    required this.type,
    required this.align,
    required this.currency,
    required this.filter,
    required this.filterable,
    required this.meta,
  });

  /// The dotted path read (`user.name`), which also keys its cells.
  final String key;

  /// The label shown, the one of the metadata otherwise, then the key.
  final String? label;

  /// A fixed width, a share of the room ([flex]) otherwise.
  final double? width;
  final int flex;

  /// Whether a tap on its header sorts the list; unsaid, any field the
  /// metadata describe but a computed one, which the server does not sort.
  final bool? sortable;

  /// The field sorted on, when it is not [key].
  final String? sortField;

  /// `date`, `datetime`, `boolean`, `number`, `currency`, `choice`; once the
  /// metadata are read, the type of the field, else `string`.
  final String? type;

  final TextAlign? align;

  /// The currency of a `currency` column, EUR otherwise.
  final String? currency;

  /// The filter of the column; with [filterable], the one of the kind of its
  /// field once the metadata are read.
  final ColumnFilter<Object>? filter;
  final bool filterable;

  /// The field the column shows, once the metadata are read.
  final MetadataField? meta;

  /// The label shown.
  String get title => label ?? meta?.label ?? key;

  /// Whether a tap on its header sorts the list.
  bool get isSortable => sortable ?? (meta != null && meta!.type != 'computed');

  /// The field a tap on its header sorts on.
  String get orderField => sortField ?? key;

  /// The column with what the metadata say of [field], its relation read in
  /// [context].
  DataTableColumn _resolve(MetadataField field, ValueSourceContext context) =>
      DataTableColumn._resolved(
        key,
        label: label,
        width: width,
        flex: flex,
        sortable: sortable,
        sortField: sortField,
        type: type ?? field.type,
        align: align,
        currency: currency,
        filter:
            filter ??
            (filterable
                ? columnFilterOf(field, label: label, context: context)
                : null),
        filterable: filterable,
        meta: field,
      );
}

/// A list read as columns, the port of `useDataTable`: a [DataIterator] that
/// knows its columns, reading their keys and [additionalFields], and
/// resolving them on the metadata, again in another workspace.
class DataTable<T extends BaseModel<T>> extends DataIterator<T> {
  DataTable(
    super.api, {
    required List<DataTableColumn> columns,
    this.additionalFields = const [],
    super.pageSize = 100,
    super.availablePageSizes = const [25, 50, 100, 150, 200],
    super.pageSizeKey = 'datatable-page-size',
    super.defaultOrderBy,
    super.exportFields,
    super.filter,
    super.params,
    super.sortable,
    super.datasetPrefix,
    super.orderable,
    super.enableSelection,
    super.append,
    super.searchField,
    super.searchFields,
    super.scrollController,
    super.url,
    super.enabled,
    super.quickFilters,
    super.views,
    super.autoRefreshOnChange,
    super.refreshDelay,
    super.watchFields,
    super.where,
  }) : _declared = columns,
       _columns = columns;

  /// The fields read without showing them.
  final List<String> additionalFields;

  List<DataTableColumn> _declared;
  List<DataTableColumn> _columns;
  MetadataModel? _model;
  Map<String, MetadataModel> _metadatas = const {};

  /// The columns, with what the metadata say once they are read.
  List<DataTableColumn> get columns => _columns;

  set columns(List<DataTableColumn> value) {
    _declared = value;
    _resolveColumns();
    fieldsChanged();
  }

  @override
  List<String> get readFields => [
    for (final column in _declared) column.key,
    ...additionalFields,
  ];

  @override
  Future<void> readMetadata() async {
    await Future.wait([super.readMetadata(), _readColumns()]);
  }

  Future<void> _readColumns() async {
    try {
      _model = await api.metadata();
      _metadatas = hasService<MetadataProvider>()
          ? await getService<MetadataProvider>().getMetadatas() ?? const {}
          : const {};
    } catch (_) {
      _model = null;
      _metadatas = const {};
    }

    _resolveColumns();
    notifyListeners();
  }

  void _resolveColumns() {
    final model = _model;

    _columns = model == null
        ? _declared
        : [for (final column in _declared) _resolved(column, model)];
  }

  DataTableColumn _resolved(DataTableColumn column, MetadataModel model) {
    final path = column.key.split('.');
    var field = model.fields[path.first];

    for (final name in path.skip(1)) {
      field = _metadatas[field?.target]?.fields[name];
    }

    return field == null
        ? column
        : column._resolve(
            field,
            ValueSourceContext(prefix: apiPrefixOf(api), metadatas: _metadatas),
          );
  }
}

/// A list read as tiles, the port of `useDataGrid`: a [DataIterator] reading
/// [fields] and [additionalFields], sized for a grid.
class DataGrid<T extends BaseModel<T>> extends DataIterator<T> {
  DataGrid(
    super.api, {
    required List<String> fields,
    List<String> additionalFields = const [],
    super.pageSize = 24,
    super.availablePageSizes = const [12, 24, 48, 96],
    super.pageSizeKey = 'datagrid-page-size',
    super.defaultOrderBy,
    super.exportFields,
    super.filter,
    super.params,
    super.sortable,
    super.datasetPrefix,
    super.orderable,
    super.enableSelection,
    super.append,
    super.searchField,
    super.searchFields,
    super.scrollController,
    super.url,
    super.enabled,
    super.quickFilters,
    super.views,
    super.autoRefreshOnChange,
    super.refreshDelay,
    super.watchFields,
    super.where,
  }) : super(fields: [...fields, ...additionalFields]);
}
