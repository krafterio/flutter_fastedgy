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
import 'column_layout.dart';
import 'custom_views.dart';
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

  /// The column at [size], its own width for null.
  DataTableColumn _sized(int? size) => size == null
      ? this
      : DataTableColumn._resolved(
          key,
          label: label,
          width: size.toDouble(),
          flex: flex,
          sortable: sortable,
          sortField: sortField,
          type: type,
          align: align,
          currency: currency,
          filter: filter,
          filterable: filterable,
          meta: meta,
        );

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

/// The columns a [DataTable] lets its users choose, its `layout` option: kept
/// for the list of [scope] (the one of its views otherwise) where its views
/// are read, or in [store]; [locked] columns move, but stay.
class DataTableLayout {
  const DataTableLayout({
    this.scope,
    this.prefix,
    this.store,
    this.locked = const [],
    this.exclude = const [],
  });

  final String? scope;
  final String? prefix;
  final ColumnStore? store;
  final List<String> locked;

  /// The fields never offered.
  final List<String> exclude;
}

/// A list read as columns, the port of `useDataTable`: a [DataIterator] that
/// knows its columns, reading their keys and [additionalFields], and
/// resolving them on the metadata, again in another workspace. With a
/// [layout], the columns shown are those its users choose.
class DataTable<T extends BaseModel<T>> extends DataIterator<T> {
  DataTable(
    super.api, {
    required List<DataTableColumn> columns,
    DataTableLayout? layout,
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
    super.groupBy,
    super.rowLimit,
    super.groupFields,
    super.groupFilter,
    super.emptyGroup,
    super.relationScopes,
    super.colorOf,
    super.autoRefreshOnChange,
    super.refreshDelay,
    super.watchFields,
    super.where,
  }) : _declared = columns,
       _columns = columns,
       layout = layout == null
           ? null
           : ColumnLayout(
               api,
               declared: [for (final column in columns) column.key],
               scope: layout.scope ?? views?.scope ?? '',
               prefix: layout.prefix ?? views?.prefix,
               store: layout.store,
               locked: layout.locked,
               exclude: layout.exclude,
             ) {
    this.layout?.addListener(_onLayout);
  }

  /// The columns its users choose, when it lets them.
  final ColumnLayout? layout;

  /// The fields read without showing them.
  final List<String> additionalFields;

  List<DataTableColumn> _declared;
  List<DataTableColumn> _columns;
  MetadataModel? _model;
  Map<String, MetadataModel> _metadatas = const {};

  /// The columns shown, with what the metadata say once they are read.
  List<DataTableColumn> get columns => _columns;

  set columns(List<DataTableColumn> value) {
    _declared = value;
    layout?.declared = [for (final column in value) column.key];
    _resolveColumns();
    fieldsChanged();
  }

  /// The columns declared, or those of the layout: the declared one an entry
  /// names, sized by it, the column of its field otherwise.
  List<DataTableColumn> get _shown {
    final layout = this.layout;

    if (layout == null) {
      return _declared;
    }

    final declared = {for (final column in _declared) column.key: column};

    return [
      for (final entry in layout.entries)
        (declared[entry.name] ?? DataTableColumn(entry.name, filterable: true))
            ._sized(entry.width),
    ];
  }

  @override
  List<String> get readFields => [
    for (final column in _shown) column.key,
    ...additionalFields,
  ];

  @override
  List<Object?>? get displayFields => layout?.written;

  @override
  void applyView(CustomView? view, Map<String, String> query) {
    super.applyView(view, query);
    layout?.applyView(view?.displayFields);
  }

  @override
  Future<void> readMetadata() async {
    await Future.wait([super.readMetadata(), _readColumns(), ?layout?.load()]);
  }

  void _onLayout() {
    _resolveColumns();
    fieldsChanged();
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
        ? _shown
        : [for (final column in _shown) _resolved(column, model)];
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

  @override
  void dispose() {
    layout
      ?..removeListener(_onLayout)
      ..dispose();
    super.dispose();
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
    super.groupBy,
    super.rowLimit,
    super.groupFields,
    super.groupFilter,
    super.emptyGroup,
    super.relationScopes,
    super.colorOf,
    super.autoRefreshOnChange,
    super.refreshDelay,
    super.watchFields,
    super.where,
  }) : super(fields: [...fields, ...additionalFields]);
}
