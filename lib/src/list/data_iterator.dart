/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show ScrollController;

import '../api/api_collection.dart';
import '../api/api_holders.dart';
import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';
import '../api/data_availability.dart';
import '../api/group_source.dart';
import '../api/grouped_api_collection.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import '../fetcher/http_error.dart';
import '../i18n/i18n.dart';
import '../logging/logger.dart';
import '../metadata/models.dart';
import '../query/order_by.dart';
import '../query/query_expression.dart' show sameExpression;
import '../workspace/workspace_provider.dart' show WorkspaceSwitchedEvent;
import 'custom_views.dart';
import 'data_groups.dart';
import 'list_url.dart';
import 'page_size.dart';
import 'quick_filter.dart';
import 'selection.dart';
import 'sortable.dart';

final _log = getLogger('DataIterator');

/// The direction a field is sorted in.
enum SortDirection { asc, desc }

/// What an import did: the rows passed, those refused and why.
class ImportResult {
  const ImportResult({
    this.success = 0,
    this.errors = 0,
    this.created = 0,
    this.updated = 0,
    this.errorDetails = const [],
    this.message,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) => ImportResult(
    success: json['success'] as int? ?? 0,
    errors: json['errors'] as int? ?? 0,
    created: json['created'] as int? ?? 0,
    updated: json['updated'] as int? ?? 0,
    errorDetails: [
      for (final one in json['error_details'] as List? ?? const [])
        if (one is Map<String, dynamic>) ImportRowError.fromJson(one),
    ],
    message: json['message'] as String?,
  );

  final int success;
  final int errors;
  final int created;
  final int updated;
  final List<ImportRowError> errorDetails;

  /// What the server said of a refused file.
  final String? message;
}

/// A row an import refused.
class ImportRowError {
  const ImportRowError({this.row, this.error = '', this.data = const {}});

  factory ImportRowError.fromJson(Map<String, dynamic> json) => ImportRowError(
    row: json['row'] as int?,
    error: '${json['error'] ?? ''}',
    data: json['data'] as Map<String, dynamic>? ?? const {},
  );

  /// Its line in the file, the header being the first.
  final int? row;

  final String error;

  /// Its values, by column of the file.
  final Map<String, dynamic> data;
}

enum _Read { page, more, held }

const _unread = Object();

String _json(Object? value) => jsonEncode(value, toEncodable: (_) => null);

bool _isEmptyFilter(Object? value) =>
    value == null || (value is List && value.isEmpty);

Object? _readExpression(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

int? _readId(String? raw) {
  final id = int.tryParse(raw ?? '');

  return id != null && id > 0 ? id : null;
}

/// A list read page by page from the server, the port of vue-fastedgy's
/// `useDataIterator`: its filter in layers, its search, the expression of a
/// query builder, its quick filters, its page size, its state in the URL, its
/// selection, its manual order, its export and its import, and its rows
/// grouped by the values of a field ([groupBy]).
///
/// It composes an [ApiCollection], which keeps reading, following the
/// realtime socket and guarding against answers out of order. Nothing is read
/// before the page size kept on the device and the metadata of the model are
/// known, nor while `enabled` is false; then one read goes out, already on the
/// right page. The changes of one turn are read once, and a workspace switch
/// starts the list over as if it were opened there.
class DataIterator<T extends BaseModel<T>> extends ChangeNotifier
    implements ActiveHolder {
  DataIterator(
    this.api, {
    this._fields,
    this._fieldsResolver,
    int pageSize = 50,
    this.availablePageSizes = const [25, 50, 100],
    String? pageSizeKey,
    this.defaultOrderBy,
    this.exportFields,
    Object? filter,
    this.params,
    bool? sortable,
    String? datasetPrefix,
    this.orderable = true,
    bool enableSelection = false,
    this.append = false,
    this.searchField = 'search_value',
    this.searchFields,
    this.scrollController,
    this.url,
    this._enabled,
    this.quickFilters = const [],
    this.views,
    String? groupBy,
    this.rowLimit = 20,
    this.groupFields = const [],
    this.groupFilter,
    this.emptyGroup = EmptyGroup.last,
    this.relationScopes = const {},
    this.colorOf,
    bool autoRefreshOnChange = true,
    this._refreshDelay = const Duration(milliseconds: 250),
    this._watchFields,
    this._where,
  }) : _filter = filter,
       _isSelectionEnabled = enableSelection,
       defaultGroupBy = groupBy,
       _autoRefresh = autoRefreshOnChange {
    // Before the collection, whose own watch reads again on the same event:
    // the list forgets its rows first, and the collection reads nothing.
    if (hasService<Bus>()) {
      _switches = getService<Bus>().on<WorkspaceSwitchedEvent>().listen(
        (_) => unawaited(_startOver()),
      );
    }

    _collection = ApiCollection<T>(
      api,
      autoRefreshOnChange: autoRefreshOnChange,
      refreshDelay: _refreshDelay,
      watchFields: _watchFields,
      where: _readsChange,
    )..addListener(_relay);

    final entry = _entry = url?.read() ?? const <String, String>{};
    final page = int.tryParse(entry['p'] ?? '') ?? 1;

    _currentPage = page > 0 ? page : 1;
    _pageSize = PageSize(
      availablePageSizes,
      fromUrl: entry['s'],
      defaultSize: pageSize,
      storageKey: pageSizeKey,
    );
    _expression = _readExpression(_filterIn(entry));
    _view = _readId(entry['cv']);
    _quick = readQuickFilters(entry['qf'], quickFilters);
    _search = entry['q'] ?? '';
    _appliedSearch = _search.trim();
    _orderBy = parseOrderBy(entry['order_by']) ?? defaultOrderBy;
    _groupBy = groupByOf(entry['g']);
    _sortable = Sortable(api, sortable: sortable, datasetPrefix: datasetPrefix);
    _selection = Selection(
      visibleIds: () => [for (final item in items) item.id],
      total: () => total,
    )..addListener(_relay);

    final scroll = int.tryParse(entry['sl'] ?? '') ?? 0;

    _restoreScroll = scrollController != null && scroll > 0 ? scroll : null;

    _rebaseline();

    url?.addListener(_onUrl);

    if (filter is Listenable) {
      filter.addListener(_changed);
    }

    _enabled?.addListener(_onEnabled);
    scrollController?.addListener(_onScroll);

    scheduleMicrotask(_start);
  }

  final ApiModel<T> api;

  final List<String>? _fields;
  final List<String> Function()? _fieldsResolver;

  final List<int> availablePageSizes;
  final List<String>? defaultOrderBy;

  /// What an export carries, the fields read otherwise.
  final List<String>? exportFields;

  /// The filter of the screen, always applied: a value, or a
  /// [ValueListenable] followed.
  final Object? _filter;

  /// More query parameters for each read (`balance=true`).
  final Map<String, String>? params;

  /// Whether a column sorts the list ([toggleSort]).
  final bool orderable;

  /// Whether the pages read follow one another instead of replacing each
  /// other.
  final bool append;

  /// The fulltext field the search is matched on.
  final String searchField;

  /// The fields the search is looked for in instead, any of them matching.
  final List<String>? searchFields;

  /// What scrolls the list, whose position is kept in the URL (`sl`) and
  /// restored on entry.
  final ScrollController? scrollController;

  /// Where the state of the list is kept, in memory only when null.
  final ListUrl? url;

  final ValueListenable<bool>? _enabled;
  final List<QuickFilter<Object?>> quickFilters;

  /// The custom views the list opens on.
  final DataIteratorViews? views;

  /// The field the rows are grouped by when nothing else says it, null for a
  /// flat list.
  final String? defaultGroupBy;

  /// The rows of a page of a group.
  final int rowLimit;

  /// More fields read on the records of an axis made of a relation.
  final List<String> groupFields;

  /// A rule added to the filter of one group, null for none.
  final Object? Function(ListGroup group)? groupFilter;

  /// Where the group of the rows with no value stands.
  final EmptyGroup emptyGroup;

  /// The rule narrowing the records an axis made of a relation shows, by
  /// field.
  final Map<String, Object?> relationScopes;

  /// The color of the group of [value] on an axis of choices of [field], null
  /// to leave it to the palette of the screen.
  final String? Function(String field, Object? value)? colorOf;

  final bool _autoRefresh;
  final Duration _refreshDelay;
  final Object? _watchFields;
  final bool Function(ResourceChangedEvent event)? _where;

  /// What the URL said of the list when it was made.
  late final Map<String, String> _entry;

  late final ApiCollection<T> _collection;
  late final PageSize _pageSize;
  late final Sortable _sortable;
  late final Selection _selection;
  StreamSubscription<WorkspaceSwitchedEvent>? _switches;

  late int _currentPage;
  Object? _customFilter;
  Object? _expression;
  int? _view;
  Object? _viewExpression = _unread;
  late Map<String, Object?> _quick;
  late String _search;
  late String _appliedSearch;
  List<String>? _orderBy;
  bool _isSelectionEnabled;
  String? _groupBy;
  MetadataModel? _meta;

  /// The groups read, for the field [_groupedBy]; the flat rows otherwise.
  GroupedApiCollection<T>? _grouped;
  String? _groupedBy;
  Object? _groupError;

  /// The writes of the list running, whose echo it does not read.
  int _writing = 0;

  bool _loaded = false;
  bool _opened = false;
  bool _ready = false;
  bool _resequencing = false;
  bool _disposed = false;

  /// While the list takes a whole state at once (a URL changed from outside,
  /// a workspace switch): no read nor write but the one that follows.
  bool _settling = false;

  bool _scheduled = false;

  /// Only the latest read counts for [loaded] and the scroll it restores.
  int _latest = 0;

  /// The fields the last read carried.
  String? _readFields;

  int? _restoreScroll;
  Timer? _searchTimer;
  Timer? _scrollTimer;

  /// What the list was last read or written with, to tell a change.
  String _lastFilter = '';
  String _lastOrder = '';
  int _lastSize = 0;
  int _lastPage = 1;
  String? _lastGroupBy;

  /// The value each key of the URL was last written with, or read with.
  Map<String, String?> _written = {};

  /// The values written to each key that the URL has not shown yet: the list
  /// knows its own writes when they land, late or not.
  final _sent = <String, List<String?>>{};

  // The rows.

  /// The rows held, those of every group shown once grouped.
  List<T> get items => _groupBy == null
      ? _collection.items
      : [for (final entry in _entries) ...entry.collection.items];

  /// How many records the filter holds, every page included; once grouped,
  /// those of the groups shown.
  int get total => _groupBy == null
      ? _collection.total
      : _entries.fold(0, (sum, entry) => sum + entry.collection.total);

  bool get loading => _groupBy == null
      ? _collection.isLoading || _collection.isLoadingMore || _resequencing
      : (_grouped?.isLoading ?? false) ||
            _resequencing ||
            _entries.any(
              (entry) =>
                  entry.collection.isLoading || entry.collection.isLoadingMore,
            );

  /// Whether a first answer came back, a failure included. A skeleton
  /// listens to it rather than to [loading]: a search does not blank the
  /// rows it narrows.
  bool get loaded => _loaded;

  /// What the last read failed with, the rows staying; once grouped, what
  /// the axis failed with, each group saying its own.
  Object? get error => _groupBy == null
      ? _collection.error
      : _groupError ?? _grouped?.source.error;

  /// Whether the rows come from the server, the mirror of the device, or
  /// could not be read.
  DataAvailability get availability => _groupBy == null
      ? _collection.availability
      : _grouped?.availability ??
            (_groupError == null
                ? DataAvailability.idle
                : DataAvailability.failed);

  @override
  bool get active => _collection.active;

  @override
  set active(bool value) {
    _collection.active = value;
    _grouped?.active = value;
  }

  // The pages.

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value < 1 || value == _currentPage) {
      return;
    }

    _currentPage = value;
    _changed();
  }

  int get pageSize => _pageSize.value;

  set pageSize(int value) {
    if (value == _pageSize.value || !availablePageSizes.contains(value)) {
      return;
    }

    _pageSize.value = value;
    _changed();
  }

  int get totalPages => pageSize > 0 ? (total / pageSize).ceil() : 0;

  /// Whether rows remain to be read after those held; once grouped, each
  /// group says it.
  bool get hasMore =>
      _groupBy == null &&
      (_collection.firstPage - 1) * pageSize + items.length < total;

  // The filter.

  /// The filter the controls of the screen set over the one of the screen.
  Object? get filter => _customFilter;

  set filter(Object? value) {
    _customFilter = value;
    _changed();
  }

  /// The expression of the query builder, kept in the URL as `f`.
  Object? get expression => _expression;

  set expression(Object? value) {
    _expression = value;
    _changed();
  }

  /// The text searched, applied after a pause in the typing and kept in the
  /// URL as `q`.
  String get search => _search;

  set search(String value) {
    if (value == _search) {
      return;
    }

    _search = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      _appliedSearch = _search.trim();
      _changed();
    });
    notifyListeners();
  }

  /// The custom view the list is on, kept in the URL as `cv`.
  int? get view => _view;

  set view(int? value) {
    _view = value;
    _changed();
  }

  /// The filters of the current view, null while they are not read.
  Object? get viewExpression =>
      identical(_viewExpression, _unread) ? null : _viewExpression;

  /// Tells the list the filters of the view it is on, which it then keeps
  /// out of the URL as long as its expression says the same.
  set viewExpression(Object? value) {
    _viewExpression = value;
    _changed();
  }

  /// Forgets the filters of the view, which the list no longer knows.
  void forgetViewExpression() {
    _viewExpression = _unread;
    _changed();
  }

  /// What the views hold besides the filters and the order.
  Map<String, ViewStateField> get viewState => views?.state ?? const {};

  /// Where the views of the list are read: where its api model answers,
  /// unless the option says otherwise.
  String get viewsPrefix => views?.prefix ?? apiPrefixOf(api);

  /// Whether the list opened on the view it starts from, or has none to
  /// open.
  bool get opened => _opened;

  /// The value of each quick filter, kept in the URL as `qf` when away from
  /// its default.
  Map<String, Object?> get quick => Map.unmodifiable(_quick);

  void setQuick(String name, Object? value) {
    _quick = {..._quick, name: value};
    _changed();
  }

  Object? get _restrictive {
    final filter = _filter;

    return filter is ValueListenable<Object?> ? filter.value : filter;
  }

  Object? _searchRule(String text) {
    final fields = searchFields;

    if (fields == null || fields.isEmpty) {
      return [searchField, 'search_fuzzy', text];
    }

    final rules = [
      for (final field in fields) [field, 'icontains', text],
    ];

    return rules.length > 1 ? ['|', rules] : rules.single;
  }

  /// What narrows the list beyond the filter of the screen.
  List<Object?> get _extraRules => [
    for (final rule in [
      _customFilter,
      _expression,
      for (final one in quickFilters) one.ruleOf(_quick[one.name]),
      if (_appliedSearch.isNotEmpty) _searchRule(_appliedSearch),
    ])
      if (!_isEmptyFilter(rule)) rule,
  ];

  /// The filter the reads send: the one of the screen, then the filter of
  /// the controls, the expression, the quick filters and the search, as one
  /// flat list of rules all applying.
  Object? get combinedFilter {
    final restrictive = _restrictive;
    final extra = _extraRules;

    if (extra.isEmpty) {
      return _isEmptyFilter(restrictive) ? null : restrictive;
    }

    final rules = restrictive == null
        ? const []
        : restrictive is List && restrictive.every((rule) => rule is List)
        ? restrictive
        : [restrictive];

    return [...rules, ...extra];
  }

  /// The filter of every row the list shows, each page included: the one it
  /// sends, or, grouped, the one of each group shown.
  Object? get rowsFilter {
    final grouped = _grouped;

    if (_groupBy == null || grouped == null) {
      return combinedFilter;
    }

    final filters = [
      for (final entry in grouped.entries) grouped.filterFor(entry.group),
    ];

    return filters.length == 1 ? filters.single : ['|', filters];
  }

  // The fields.

  /// The fields a read carries: the id, those the screen reads, the field of
  /// the manual order.
  List<String> get fields {
    final sortableField = _sortable.sortableField;

    return {
      'id',
      ...readFields,
      if (_sortable.isSortable && sortableField != null) sortableField,
    }.toList();
  }

  /// The fields the screen reads: those it resolves, else those it gives.
  @protected
  List<String> get readFields => _fieldsResolver?.call() ?? _fields ?? const [];

  /// Tells the list its fields may have changed: a field it has not read yet
  /// reads the rows again.
  @protected
  void fieldsChanged() => _changed();

  // The order.

  List<String>? get orderBy => _orderBy;

  set orderBy(List<String>? value) {
    _orderBy = value;
    _changed();
  }

  /// Sorts on [field]: ascending, then descending, then back to
  /// [defaultOrderBy]; another field starts ascending.
  void toggleSort(String field) {
    if (field.isEmpty || !orderable) {
      return;
    }

    final current = orderByTerm(_orderBy?.firstOrNull);

    if (current.field != field) {
      orderBy = ['$field:asc'];
    } else if (current.direction != 'desc') {
      orderBy = ['$field:desc'];
    } else {
      final byDefault = defaultOrderBy;

      // A default order on this very field would leave the click without
      // effect: it turns around instead.
      orderBy = orderByTerm(byDefault?.firstOrNull).field == field
          ? ['$field:asc']
          : byDefault;
    }
  }

  /// The direction [field] is sorted in, a term without one being ascending.
  SortDirection? getSortDirection(String field) {
    for (final term in _orderBy ?? const <String>[]) {
      final read = orderByTerm(term);

      if (read.field == field) {
        return read.direction == 'desc'
            ? SortDirection.desc
            : SortDirection.asc;
      }
    }

    return null;
  }

  // The manual order.

  /// Whether the rows can be ordered by hand: the model is sortable and
  /// nothing narrows the list but the filter of the screen.
  bool get isSortable => _sortable.isSortable && _extraRules.isEmpty;

  /// Saves the order of [ids], moved to the group [groupValue] of
  /// [groupField] when given: the rows take it at once, the order is sent
  /// with the rank of the first of them in the whole list, then the rows are
  /// read again. A refusal reads them again and is thrown.
  Future<void> resequence(
    List<int> ids, {
    String? groupField,
    Object? groupValue,
  }) async {
    if (_sortable.isSortable && !isSortable) {
      _log.warning('Resequencing waits for the list to be narrowed by nothing');
      await refresh();

      return;
    }

    final rows = _groupBy == null
        ? _collection
        : _holding(ids.firstOrNull)?.collection ?? _collection;

    _reorder(rows, ids);
    _resequencing = true;
    notifyListeners();

    try {
      await _sortable.resequence(
        ids,
        sequenceOffset:
            (rows.firstPage - 1) * (_groupBy == null ? pageSize : rowLimit),
        groupField: groupField,
        groupValue: groupValue,
      );
      await refresh();
    } catch (_) {
      await refresh();
      rethrow;
    } finally {
      _resequencing = false;

      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Puts the rows of [ids] in their order, in the places they held among
  /// those of [collection].
  void _reorder(ApiCollection<T> collection, List<int> ids) {
    final rows = collection.items;
    final moved = [
      for (final id in ids) ?rows.where((row) => row.id == id).firstOrNull,
    ];
    final slots = [
      for (final (index, row) in rows.indexed)
        if (ids.contains(row.id)) index,
    ];

    if (moved.length != slots.length) {
      return;
    }

    final ordered = [...rows];

    for (final (index, slot) in slots.indexed) {
      ordered[slot] = moved[index];
    }

    collection.reorder(ordered);
  }

  // The groups.

  /// The field the rows are grouped by, null for a flat list; kept in the URL
  /// as `g` when it is not [defaultGroupBy], `none` for a flat list then.
  String? get groupBy => _groupBy;

  set groupBy(String? value) {
    _groupBy = value;
    _changed();
  }

  /// The grouping a URL or a view says: [defaultGroupBy] when it says
  /// nothing, none for `none`.
  String? groupByOf(String? said) => said == null
      ? defaultGroupBy
      : said == 'none'
      ? null
      : said;

  List<GroupedEntry<T>> get _entries =>
      _groupBy == null ? const [] : _grouped?.entries ?? const [];

  /// The groups, in the order of their axis.
  List<DataGroup<T>> get groups => [
    for (final entry in _entries)
      DataGroup(
        entry.group,
        entry.collection,
        _grouped!.filterFor(entry.group),
      ),
  ];

  /// The page of the axis, when it is made of records.
  int get groupPage => _grouped?.groupPage ?? 1;

  int get groupTotalPages => _grouped?.groupTotalPages ?? 0;

  Future<void> setGroupPage(int page) async {
    await _grouped?.setGroupPage(page);
  }

  /// The fields the rows can be grouped by, once the metadata are read.
  List<MetadataField> get groupableFields => [
    for (final field in _meta?.fields.values ?? const <MetadataField>[])
      if (isGroupable(field)) field,
  ];

  /// Whether a row can go to another group: the field of the groups is
  /// written, neither read-only nor computed.
  bool get canMoveToGroup {
    final field = _meta?.fields[_groupBy];

    return field != null && !field.readonly && field.type != 'computed';
  }

  /// Whether the groups can be put in another order: the axis is made of
  /// records ordered by hand.
  bool get canMoveGroups {
    final source = _grouped?.source;

    return source is RelationGroupSource && source.sequenceField != null;
  }

  GroupedEntry<T>? _holding(Object? id) =>
      _entries.where((entry) => entry.collection.byId(id) != null).firstOrNull;

  /// The group [item] belongs to by its value, null when it does not carry
  /// the field of the groups.
  GroupedEntry<T>? _groupOf(T item) {
    final field = _groupBy;

    if (field == null || !item.data.containsKey(field)) {
      return null;
    }

    final raw = item.data[field];
    final value = raw is Map ? raw['id'] : raw;

    return _entries
        .where(
          (entry) => entry.group.isEmptyBucket
              ? value == null
              : entry.group.value == value,
        )
        .firstOrNull;
  }

  /// Moves [item] to [group], at [index] among its rows, at their end without
  /// one: at once on the screen, its value and the totals of both groups
  /// included, then the order of the group with its value in one request. A
  /// field of the workspace, which that request does not write, is written on
  /// the row first; without a manual order to keep, the value alone is
  /// written. A refusal reads the groups again and is thrown.
  Future<void> moveTo(T item, DataGroup<T> group, [int? index]) async {
    final grouped = _grouped;
    final field = _groupBy;
    final target = _entries
        .where((entry) => entry.group.key == group.key)
        .firstOrNull;

    if (grouped == null || field == null || target == null) {
      throw StateError('The list shows no group ${group.key}');
    }

    final from = _holding(item.id);
    final inPlace = from?.collection == target.collection;
    final ordered = isSortable;
    final extra = _meta?.fields[field]?.extra ?? false;

    if (!inPlace && !canMoveToGroup) {
      throw StateError('The field $field is not written');
    }

    if (inPlace && !ordered) {
      return;
    }

    final value = target.group.isEmptyBucket ? null : target.group.value;
    final moved = inPlace
        ? item
        : api.fromJson({...item.data, field: target.group.record ?? value});
    final rows = [
      for (final row in target.collection.items)
        if (row.id != item.id) row,
    ];

    rows.insert(
      index == null || index < 0 || index > rows.length ? rows.length : index,
      moved,
    );

    if (!inPlace) {
      from?.collection.removeLocal(item.id);
      target.collection.upsertLocal(moved);
    }

    target.collection.reorder(rows);

    try {
      await writing(() async {
        if (!inPlace && (extra || !ordered)) {
          await api.update(item.id!, api.fromJson({field: value}));
        }

        if (ordered) {
          final grouping = !inPlace && !extra;

          await _sortable.resequence(
            [...rows.map((row) => row.id).whereType<int>()],
            sequenceOffset: (target.collection.firstPage - 1) * rowLimit,
            groupField: grouping ? field : null,
            groupValue: grouping ? value : null,
          );
        }
      });
    } catch (_) {
      await grouped.refresh();
      rethrow;
    }
  }

  /// Moves [group] to [index] on the axis, the group with no value keeping
  /// its place: at once on the screen, then the order of the axis is sent to
  /// the model of its records. A refusal reads the axis again and is thrown.
  Future<void> moveGroup(DataGroup<T> group, int index) async {
    final grouped = _grouped;
    final source = grouped?.source;

    if (grouped == null ||
        source is! RelationGroupSource ||
        source.sequenceField == null) {
      throw StateError('The groups of the list are not ordered by hand');
    }

    if (group.isEmptyBucket) {
      return;
    }

    final entries = grouped.entries;
    final emptyFirst = entries.firstOrNull?.group.isEmptyBucket ?? false;
    final keys = [
      for (final entry in entries)
        if (!entry.group.isEmptyBucket && entry.group.key != group.key)
          entry.group.key,
    ];
    final at = (emptyFirst ? index - 1 : index).clamp(0, keys.length);

    keys.insert(at, group.key);

    final values = {for (final entry in entries) entry.group.key: entry.group};
    final ids = [for (final key in keys) values[key]!.value];

    source.reorder(ids);
    grouped.reorderGroups([
      if (emptyFirst) 'empty',
      ...keys,
      if (!emptyFirst && entries.any((entry) => entry.group.isEmptyBucket))
        'empty',
    ]);

    try {
      await _sortable.resequenceOf(
        source.target,
        [...ids.whereType<int>()],
        field: source.sequenceField!,
        sequenceOffset: (source.page - 1) * source.limit,
      );
    } catch (_) {
      await grouped.reloadAxis();
      rethrow;
    }
  }

  /// Runs [write], whose echo the list does not read: its rows already say
  /// what it changes.
  Future<R> writing<R>(Future<R> Function() write) async {
    _writing += 1;

    try {
      return await write();
    } finally {
      // An api hands what a write announces to the bus on a timer, once the
      // write returned to its caller: the changes are read again after it.
      Timer.run(() => _writing -= 1);
    }
  }

  /// Whether a change is read again: not the echo of a write of the list, a
  /// move or an edit.
  bool _readsChange(ResourceChangedEvent event) =>
      _writing == 0 && (_where?.call(event) ?? true);

  void _dropGroups() {
    _grouped
      ?..removeListener(_relay)
      ..dispose();
    _grouped = null;
    _groupedBy = null;
    _groupError = null;
  }

  // The selection.

  bool get isSelectionEnabled => _isSelectionEnabled;

  set isSelectionEnabled(bool value) {
    _isSelectionEnabled = value;
    notifyListeners();
  }

  Selection get selection => _selection;

  // Reading.

  bool get _isEnabled => _enabled?.value ?? true;

  bool get _canRead => _ready && _isEnabled && !_disposed;

  /// Reads the metadata the list depends on: the manual order, the fields
  /// that group, and for a table its columns. Read on opening and again in
  /// another workspace.
  @protected
  Future<void> readMetadata() async {
    await Future.wait([_sortable.readMetadata(), _readModel()]);
  }

  Future<void> _readModel() async {
    try {
      _meta = await api.metadata();
    } catch (_) {
      _meta = null;
    }
  }

  Future<void> _start() async {
    if (_disposed) {
      return;
    }

    await Future.wait([_pageSize.ready, readMetadata(), _open()]);

    if (_disposed) {
      return;
    }

    _ready = true;
    _rebaseline();
    await _read();
  }

  /// Opens the list on a view before its first read: the one a link names
  /// when it carries no filter of its own, else, for a URL saying nothing of
  /// the list, the favorite of the user, else the one of everyone.
  Future<void> _open() async {
    final views = this.views;

    if (views == null) {
      _opened = true;

      return;
    }

    final keys = [
      'p',
      's',
      'order_by',
      'q',
      'sl',
      'f',
      'cv',
      'qf',
      'g',
      for (final one in views.state.values) ?one.key,
    ];
    final linked = _entry.containsKey('f') ? null : _view;

    if (linked == null && keys.any(_entry.containsKey)) {
      _opened = true;

      return;
    }

    final before = _view;
    final start = await _openingView(id: linked);

    // A view chosen while it was read is the one the list shows.
    if (_disposed || _view != before) {
      _opened = true;

      return;
    }

    final query = url?.read() ?? const <String, String>{};

    if (start == null) {
      _view = null;
    } else {
      _expression = start.filters;
      _viewExpression = start.filters;
      _view = start.id;

      if (!query.containsKey('order_by')) {
        _orderBy = start.orderBy ?? defaultOrderBy;
      }

      if (!query.containsKey('g')) {
        _groupBy = groupByOf(start.groupBy);
      }

      _applyState(start, query);
    }

    _opened = true;
  }

  Future<CustomView?> _openingView({int? id}) async {
    final model = await api.resolveModelName();

    return model == null
        ? null
        : openingView(
            model,
            scope: views!.scope,
            prefix: viewsPrefix,
            id: id,
            fetcher: api.fetcher,
          );
  }

  /// Holds what [view] says besides its filters and its order, unless
  /// [query] says it.
  void _applyState(CustomView? view, Map<String, String> query) {
    for (final MapEntry(key: name, value: one) in viewState.entries) {
      final key = one.key;

      if (key == null || !query.containsKey(key)) {
        one.set(view?[name]);
      }
    }
  }

  void _onEnabled() {
    if (_isEnabled) {
      unawaited(_read());
    }
  }

  Future<void> _read([_Read mode = _Read.page]) async {
    if (!_canRead) {
      return;
    }

    final run = ++_latest;
    final field = _groupBy;

    _readFields = fields.join(',');

    // Another shape, flat or grouped by another field: the rows held go, and
    // the flat ones no longer follow the changes meanwhile.
    if (field != _groupedBy) {
      _dropGroups();
      _collection.reset();
      _groupedBy = field;
      _loaded = false;
      notifyListeners();
    }

    if (field != null) {
      await _readGroups(run, field, mode);
    } else if (mode == _Read.more) {
      await _collection.loadMore();
    } else {
      await _collection.readPages(
        mode == _Read.held
            ? _collection.firstPage
            : append
            ? 1
            : _currentPage,
        _currentPage,
        query: ListQuery(
          size: pageSize,
          fields: fields,
          filter: combinedFilter,
          orderBy: _orderBy,
          params: params,
        ),
      );
    }

    if (run != _latest || _disposed) {
      return;
    }

    _loaded = true;
    _restore();
    notifyListeners();
  }

  /// Reads the groups by [field]: their axis and their rows the first time,
  /// their rows again after.
  Future<void> _readGroups(int run, String field, _Read mode) async {
    final current = _grouped;

    if (current != null) {
      await (mode == _Read.held
          ? current.refresh()
          : current.refine(
              filter: combinedFilter,
              orderBy: _orderBy,
              fields: fields,
            ));

      return;
    }

    final colorOf = this.colorOf;
    final source = await resolveGroupSource(
      api,
      field,
      limit: 50,
      emptyLabel: t('No value'),
      yesLabel: t('Yes'),
      noLabel: t('No'),
      includeEmpty: emptyGroup == EmptyGroup.none ? false : null,
      emptyFirst: emptyGroup == EmptyGroup.first,
      fields: groupFields,
      filter: relationScopes[field],
      colorOf: colorOf == null ? null : (value) => colorOf(field, value),
    );

    if (run != _latest || _disposed) {
      source?.dispose();

      return;
    }

    if (source == null) {
      _groupError = t("This field can't be grouped.");

      return;
    }

    final grouped = _grouped = GroupedApiCollection<T>(
      api,
      source,
      fields: fields,
      orderBy: _orderBy,
      filter: combinedFilter,
      rowLimit: rowLimit,
      refreshDelay: _refreshDelay,
      watchFields: _watchFields,
      groupFilter: groupFilter,
      where: (event) => _autoRefresh && _readsChange(event),
    );

    grouped
      ..active = active
      ..addListener(_relay);
    await grouped.load();
  }

  /// Reads the next page and adds it to the rows, whether the list appends
  /// or pages. Nothing while a read runs, nor without more rows.
  Future<void> loadMore() async {
    if (loading || !hasMore || !_canRead) {
      return;
    }

    _currentPage += 1;
    _lastPage = _currentPage;
    _writeShown();
    notifyListeners();

    await _read(_Read.more);
  }

  /// Reads again the rows shown, every page an appended list holds at once,
  /// without going back to the first page nor blanking the screen.
  Future<void> refresh() => _settling ? Future.value() : _read(_Read.held);

  void resetPagination() => currentPage = 1;

  /// Loads the rows that follow until the one of [id], and returns it; null
  /// once the list has no more rows.
  Future<T?> reach(Object id) async {
    while (byId(id) == null && hasMore && !loading) {
      final held = items.length;

      await loadMore();

      if (items.length == held) {
        break;
      }
    }

    return byId(id);
  }

  T? byId(Object? id) => _groupBy == null
      ? _collection.byId(id)
      : _holding(id)?.collection.byId(id);

  /// Puts [item] in place of the row holding its id, or adds it; once
  /// grouped, in the group of its value, which it leaves another for.
  bool upsertLocal(T item, {bool prepend = false}) {
    if (_groupBy == null) {
      return _collection.upsertLocal(item, prepend: prepend);
    }

    final from = _holding(item.id);
    final into = _groupOf(item) ?? from;

    if (into == null) {
      return false;
    }

    if (from != null && from.collection != into.collection) {
      from.collection.removeLocal(item.id);
    }

    return into.collection.upsertLocal(item, prepend: prepend);
  }

  bool removeLocal(Object? id) => _groupBy == null
      ? _collection.removeLocal(id)
      : _holding(id)?.collection.removeLocal(id) ?? false;

  /// Puts the rows in the order of [ordered]; once grouped, those of the group
  /// holding the first of them.
  void reorder(List<T> ordered) =>
      (_groupBy == null
              ? _collection
              : _holding(ordered.firstOrNull?.id)?.collection)
          ?.reorder(ordered);

  Future<T> readItem(Object id) => _groupBy == null
      ? _collection.readItem(id)
      : api.get(id, options: FieldsOptions(fields: fields));

  // What changed.

  void _relay() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Something the reads depend on changed: the changes of this turn are
  /// read together.
  void _changed() {
    if (_disposed) {
      return;
    }

    notifyListeners();

    if (_scheduled) {
      return;
    }

    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _scheduled = false;

    if (_disposed) {
      return;
    }

    final filter = _json(combinedFilter);
    final filterChanged = filter != _lastFilter;
    final order = _json(_orderBy);
    final reload =
        filterChanged ||
        order != _lastOrder ||
        pageSize != _lastSize ||
        _groupBy != _lastGroupBy;
    final pageChanged = _currentPage != _lastPage;

    // A selection made under other rules is not this list's.
    if (filterChanged) {
      _selection.clear();
    }

    _lastFilter = filter;
    _lastOrder = order;
    _lastSize = pageSize;
    _lastGroupBy = _groupBy;

    if (_settling) {
      _lastPage = _currentPage;

      return;
    }

    if (reload) {
      _currentPage = 1;
    }

    _lastPage = _currentPage;
    _writeShown();

    if (reload || (pageChanged && !append)) {
      unawaited(_read());
    } else if (_latest > 0 && fields.join(',') != _readFields) {
      unawaited(_read(_Read.held));
    }
  }

  /// Takes the state as it stands as the one read and written.
  void _rebaseline() {
    final filter = _json(combinedFilter);

    if (filter != _lastFilter) {
      _selection.clear();
    }

    _lastFilter = filter;
    _lastOrder = _json(_orderBy);
    _lastSize = pageSize;
    _lastPage = _currentPage;
    _lastGroupBy = _groupBy;
    _written = {for (final key in _shownAs.keys) key: _shownAs[key]!()};
  }

  // The URL.

  /// The expression as `f` says it: nothing for a list on its view as the
  /// view says it, the expression once it moves away from it, `null` written
  /// out for filters cleared off a view.
  String? _writtenExpression() {
    final current = _expression;

    if (_view == null) {
      return _isEmptyFilter(current) ? null : jsonEncode(current);
    }

    if (!identical(_viewExpression, _unread) &&
        sameExpression(current, _viewExpression)) {
      return null;
    }

    return jsonEncode(current);
  }

  /// What each key followed says of the list as it stands.
  late final Map<String, String? Function()> _shownAs = {
    'p': () => _currentPage > 1 ? '$_currentPage' : null,
    's': () => '$pageSize',
    'order_by': () => _json(_orderBy) == _json(defaultOrderBy)
        ? null
        : formatOrderBy(_orderBy),
    'q': () => _appliedSearch.isEmpty ? null : _appliedSearch,
    'f': _writtenExpression,
    'cv': () => _view == null ? null : '$_view',
    'qf': () => writeQuickFilters(_quick, quickFilters),
    'g': () => _groupBy == defaultGroupBy ? null : _groupBy ?? 'none',
  };

  /// The raw expression of a URL: `f`, or the `filter` older links carry
  /// when the list has no prefix.
  String? _filterIn(Map<String, String> query) =>
      query['f'] ??
      (url == null || url!.prefix.isNotEmpty ? null : query['filter']);

  /// Writes the keys whose value moved since they were last written.
  void _writeShown() {
    final patch = <String, String?>{};

    for (final MapEntry(:key, value: shown) in _shownAs.entries) {
      final value = shown();

      if (value != _written[key]) {
        patch[key] = value;
        _written[key] = value;
      }
    }

    _writeQuery(patch);
  }

  void _writeQuery(Map<String, String?> patch) {
    final url = this.url;

    if (url == null || _settling || patch.isEmpty) {
      return;
    }

    final shown = url.read();

    for (final MapEntry(:key, :value) in patch.entries) {
      final text = value == null || value.isEmpty ? null : value;

      if (text != shown[key]) {
        (_sent[key] ??= []).add(text);
      }
    }

    url.write(patch);
  }

  /// Whether the URL moved under the list: a key saying something the list
  /// neither holds nor wrote. A size the URL leaves out keeps the one chosen.
  bool _movedFromOutside(Map<String, String> query) {
    var moved = false;

    for (final MapEntry(:key, value: current) in _shownAs.entries) {
      final value = key == 'f' ? _filterIn(query) : query[key];
      final pending = _sent[key] ?? const [];
      final own = pending.indexOf(value);

      if (own >= 0) {
        _sent[key] = pending.sublist(own + 1);
      } else if (value != current() && !(key == 's' && value == null)) {
        moved = true;
      }
    }

    return moved;
  }

  /// Holds what a URL changed from outside says (back, forward, a link
  /// followed to the same screen), as a list entered on it would, then reads
  /// once.
  Future<void> _followUrl() async {
    final query = url!.read();

    if (_settling || !_opened || !_movedFromOutside(query)) {
      return;
    }

    _sent.clear();
    _settling = true;

    try {
      final page = int.tryParse(query['p'] ?? '') ?? 1;
      final size = int.tryParse(query['s'] ?? '');

      _currentPage = page > 0 ? page : 1;

      if (size != null && availablePageSizes.contains(size)) {
        _pageSize.value = size;
      }

      _searchTimer?.cancel();
      _search = query['q'] ?? '';
      _appliedSearch = _search.trim();
      _quick = readQuickFilters(query['qf'], quickFilters);

      final linked = _readId(query['cv']);

      if (linked != _view) {
        CustomView? named;

        if (linked != null && views != null) {
          named = await _openingView(id: linked);
          _applyState(named, query);
        }

        _view = views != null ? named?.id : linked;
        _viewExpression = named != null ? named.filters : _unread;
      }

      final raw = _filterIn(query);

      _expression = raw != null
          ? _readExpression(raw)
          : _view != null
          ? viewExpression
          : null;
      _orderBy = parseOrderBy(query['order_by']) ?? defaultOrderBy;
      _groupBy = groupByOf(query['g']);
    } finally {
      _settling = false;
    }

    if (_disposed) {
      return;
    }

    _rebaseline();
    notifyListeners();
    await _read();
  }

  /// Starts over in the workspace switched to, as a list opened there at
  /// once: its state back to the opening, the metadata of that workspace read
  /// and what hangs on them resolved again, then one read. The rows of the
  /// other workspace go meanwhile, and an answer of it lands nowhere.
  Future<void> _startOver() async {
    _sent.clear();
    _settling = true;
    ++_latest;
    _collection.reset();
    _dropGroups();

    try {
      _selection.clear();
      _loaded = false;
      _currentPage = 1;
      _searchTimer?.cancel();
      _search = '';
      _appliedSearch = '';
      _customFilter = null;
      _quick = readQuickFilters(null, quickFilters);
      _view = null;
      _viewExpression = _unread;
      _expression = null;
      _orderBy = defaultOrderBy;
      _groupBy = defaultGroupBy;
      _restoreScroll = null;
      notifyListeners();

      await readMetadata();

      if (views != null) {
        final start = await _openingView();

        _applyState(start, const {});

        if (start != null) {
          _expression = start.filters;
          _viewExpression = start.filters;
          _view = start.id;
          _orderBy = start.orderBy ?? defaultOrderBy;
          _groupBy = groupByOf(start.groupBy);
        }
      }
    } finally {
      _settling = false;
    }

    if (_disposed) {
      return;
    }

    _rebaseline();
    _writeQuery({
      'p': null,
      'q': null,
      'qf': null,
      'sl': null,
      'f': _written['f'],
      'cv': _written['cv'],
      'order_by': _written['order_by'],
      'g': _written['g'],
    });
    _scrollTo(0);
    notifyListeners();
    await _read();
  }

  void _onUrl() => unawaited(_followUrl());

  // The scroll.

  void _onScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 350), () {
      final controller = scrollController;

      if (controller == null || !controller.hasClients) {
        return;
      }

      final top = controller.offset.round();

      _writeQuery({'sl': top > 0 ? '$top' : null});
    });
  }

  void _restore() {
    final top = _restoreScroll;

    if (top != null) {
      _restoreScroll = null;
      _scrollTo(top);
    }
  }

  void _scrollTo(int top) {
    final controller = scrollController;

    if (controller == null) {
      return;
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && controller.hasClients) {
        controller.jumpTo(
          math.min(top.toDouble(), controller.position.maxScrollExtent),
        );
      }
    });
  }

  // Export and import.

  /// The export of every record of the filter, in its order, as the bytes of
  /// a `csv`, `xlsx` or `json` file.
  Future<Uint8List> exportData({String format = 'csv'}) async {
    final response = await api.export(
      query: ExportQuery(
        format: format,
        fields: exportFields ?? fields,
        filter: combinedFilter,
        orderBy: _orderBy,
      ),
    );
    final data = response.data;

    return data is Uint8List ? data : Uint8List.fromList(data as List<int>);
  }

  /// Imports a `csv`, `xlsx` or `ods` file, the separator of a CSV being
  /// [delimiter], found by the server when left out. A file refused row by
  /// row is a result, not a failure. The rows are read again once one passed.
  Future<ImportResult> importData(
    List<int> bytes,
    String fileName, {
    String? delimiter,
  }) async {
    try {
      final response = await api.import(bytes, fileName, delimiter: delimiter);
      final result = ImportResult.fromJson(
        response.data as Map<String, dynamic>,
      );

      if (result.success > 0) {
        await refresh();
      }

      return result;
    } catch (error) {
      final body = switch (error) {
        HttpError(:final data) => data,
        DioException(:final response) => response?.data,
        _ => null,
      };
      final detail = body is Map ? body['detail'] : null;

      if (detail is Map<String, dynamic> && detail['error_details'] != null) {
        return ImportResult.fromJson(detail);
      }

      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _scrollTimer?.cancel();
    unawaited(_switches?.cancel());
    url?.removeListener(_onUrl);

    final filter = _filter;

    if (filter is Listenable) {
      filter.removeListener(_changed);
    }

    _enabled?.removeListener(_onEnabled);
    scrollController?.removeListener(_onScroll);
    _dropGroups();
    _collection
      ..removeListener(_relay)
      ..dispose();
    _selection
      ..removeListener(_relay)
      ..dispose();
    _pageSize.dispose();
    super.dispose();
  }
}

/// The filter of an action on the selection of [list]: the ids chosen, or,
/// every record shown being chosen, their filter with the rows unchecked
/// left out.
Object? selectionFilter(DataIterator<dynamic> list) {
  final selection = list.selection;

  if (!selection.all) {
    return [
      'id',
      'in',
      [...selection.ids],
    ];
  }

  final filter = list.rowsFilter;
  final excluded = selection.excluded;

  if (excluded.isEmpty) {
    return filter;
  }

  final rule = ['id', 'not in', excluded];

  if (filter == null) {
    return rule;
  }

  return [
    ...(filter is List && filter.every((one) => one is List)
        ? filter
        : [filter]),
    rule,
  ];
}
