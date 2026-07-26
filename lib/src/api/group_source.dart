/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
import '../metadata/display_fields.dart';
import '../metadata/metadata_provider.dart';
import 'api_collection.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';

/// One bucket of a grouped list: what its header says, and the filter rule that
/// selects the rows belonging to it.
class ListGroup {
  /// Stable identity of the bucket across group pages — a bucket whose key did
  /// not move keeps its rows, its page and its scroll offset.
  final String key;

  /// Value of the grouped field, null for the bucket of records that have none.
  final Object? value;

  /// Header text.
  final String label;

  /// X-Filter rule selecting this bucket's rows, ANDed with the list's own
  /// filter.
  final List<Object?> predicate;

  /// Whether this is the bucket of records with no value for the field.
  final bool isEmptyBucket;

  const ListGroup({
    required this.key,
    required this.label,
    required this.predicate,
    this.value,
    this.isEmptyBucket = false,
  });

  @override
  String toString() => 'ListGroup($key)';
}

/// The axis of a grouped list: which buckets exist, one page of them at a time.
///
/// FastEdgy has no `group_by`, so a grouped list is emulated the way Odoo's
/// read_group is: this enumerates the buckets, and the caller reads the rows of
/// each one with its own request. That is what buys every bucket an exact count
/// and a pagination of its own.
///
/// A source is a plain object, not a listenable: it is read when the caller
/// loads it or turns its page. [watchPath] is what a caller watches to know the
/// axis itself went stale.
abstract class GroupSource {
  /// Buckets of the current page, in the order the header shows them.
  List<ListGroup> get groups;

  /// 1-based page of buckets.
  int get page;

  /// Buckets per page.
  int get limit;

  /// Total number of buckets on the axis.
  int get total;

  int get totalPages;

  /// Whether [total] is a count and not an estimate. False would mark a source
  /// that can only approximate its axis; every source here is exact.
  bool get isTotalExact;

  bool get isLoading;

  /// Whether the buckets come from the local mirror rather than the server.
  bool get fromCache;

  /// True when the axis could not be enumerated at all — the caller has no
  /// bucket to show and should say a connection is required.
  bool get requiresConnection;

  /// Why the last read of the axis failed, null when it did not. A refusal is
  /// not [requiresConnection]: the server answered, so the caller shows a
  /// retry rather than a connection notice.
  Object? get error;

  /// Resource path whose changes invalidate the axis, null for an axis that
  /// needs no request. A caller watching the bus reloads on it.
  String? get watchPath;

  bool get hasNextPage => page < totalPages;

  bool get hasPreviousPage => page > 1;

  Future<bool> load();

  Future<bool> setPage(int page);

  void dispose();
}

/// Axis of a `choice` field, straight from the metadata: the buckets are the
/// enum members the server declared, in its own order, and enumerating them
/// costs **no request at all**.
class ChoiceGroupSource extends GroupSource {
  ChoiceGroupSource({
    required this.field,
    required Map<String, String> choices,
    this.limit = 20,
    bool includeEmpty = true,
    String emptyLabel = '',
    Object? Function(String key)? valueOf,
    String Function(String key, String label)? labelOf,
  }) {
    for (final entry in choices.entries) {
      // The metadata key is the *enum member name*; the stored value happens to
      // be the same in every model here, and valueOf is where that stops being
      // an assumption.
      final value = valueOf == null ? entry.key : valueOf(entry.key);

      _all.add(
        ListGroup(
          key: 'value:${entry.key}',
          value: value,
          label: labelOf == null
              ? entry.value
              : labelOf(entry.key, entry.value),
          predicate: [field, '=', value],
        ),
      );
    }

    if (includeEmpty) {
      _all.add(
        ListGroup(
          key: 'empty',
          label: emptyLabel,
          predicate: [field, 'is empty'],
          isEmptyBucket: true,
        ),
      );
    }
  }

  final String field;

  @override
  final int limit;

  final List<ListGroup> _all = [];
  int _page = 1;

  @override
  List<ListGroup> get groups {
    final start = (_page - 1) * limit;

    if (start >= _all.length) {
      return const [];
    }

    return _all.sublist(start, (start + limit).clamp(0, _all.length));
  }

  @override
  int get page => _page;

  @override
  int get total => _all.length;

  @override
  int get totalPages => _all.isEmpty ? 1 : (_all.length / limit).ceil();

  @override
  bool get isTotalExact => true;

  @override
  bool get isLoading => false;

  @override
  bool get fromCache => false;

  /// Never: the enum came with the metadata the app already holds.
  @override
  bool get requiresConnection => false;

  @override
  Object? get error => null;

  @override
  String? get watchPath => null;

  @override
  Future<bool> load() async => true;

  @override
  Future<bool> setPage(int page) async {
    _page = page.clamp(1, totalPages);

    return true;
  }

  @override
  void dispose() {}
}

/// Axis of a many2one field: the buckets are the records of the target model,
/// read as an ordinary paginated list — so it falls back to the mirror when the
/// target is replicated, and honours the target's own `default_order_by` unless
/// told otherwise.
class RelationGroupSource extends GroupSource {
  RelationGroupSource({
    required this.field,
    required ApiModel<GenericBaseModel> target,
    this.labelField = 'name',
    this.limit = 20,
    this.includeEmpty = true,
    this.emptyLabel = '',
    dynamic orderBy,
  }) : _target = target,
       _collection = ApiCollection<GenericBaseModel>(
         target,
         fields: ['id', labelField],
         orderBy: orderBy,
         limit: limit,
         // The owner of this axis holds the single bus subscription: N buckets
         // reloading themselves on every mutation is what this design exists to
         // avoid.
         autoRefreshOnChange: false,
       );

  final String field;
  final String labelField;
  final bool includeEmpty;
  final String emptyLabel;
  final ApiModel<GenericBaseModel> _target;
  final ApiCollection<GenericBaseModel> _collection;

  @override
  final int limit;

  /// Whether the axis was actually enumerated. An unreachable target must not
  /// be reported as an axis holding a single "no value" bucket: nothing is
  /// known, not "everything has no value".
  bool get _readable => _collection.isLoaded && !_collection.requiresConnection;

  @override
  List<ListGroup> get groups => [
    for (final record in _collection.items)
      ListGroup(
        key: 'id:${record.id}',
        value: record.id,
        label: record.getString(labelField) ?? '#${record.id}',
        predicate: [field, '=', record.id],
      ),
    // The bucket of records with no relation is not a row of the target model:
    // it is appended once, at the end of the axis.
    if (includeEmpty && _readable && !_collection.hasNextPage)
      ListGroup(
        key: 'empty',
        label: emptyLabel,
        predicate: [field, 'is empty'],
        isEmptyBucket: true,
      ),
  ];

  @override
  int get page => _collection.page;

  @override
  int get total => _collection.total + (includeEmpty && _readable ? 1 : 0);

  @override
  int get totalPages => _collection.totalPages < 1 ? 1 : _collection.totalPages;

  @override
  bool get isTotalExact => true;

  @override
  bool get isLoading => _collection.isLoading;

  @override
  bool get fromCache => _collection.isFromCache;

  @override
  bool get requiresConnection => _collection.requiresConnection;

  @override
  Object? get error => _collection.error;

  @override
  String? get watchPath => _target.resolvedBasePath;

  @override
  Future<bool> load() => _collection.load(
    query: ListQuery(
      fields: ['id', labelField],
      orderBy: _collection.orderBy,
      limit: limit,
    ),
  );

  @override
  Future<bool> setPage(int page) => _collection.setPage(page);

  @override
  void dispose() => _collection.dispose();
}

/// The source able to group [api]'s list by [field], or **null** when no source
/// can.
///
/// That null is the framework answering "this field is not groupable": FastEdgy
/// metadata has no such flag, and this is what a menu reads to decide what to
/// offer. Today it means everything but a `choice` and a many2one — a date axis
/// in particular needs a server-side `GROUP BY` to know which periods hold rows
/// at all.
Future<GroupSource?> resolveGroupSource<T extends BaseModel<T>>(
  ApiModel<T> api,
  String field, {
  int limit = 20,
  String emptyLabel = '',
  String? labelField,
  bool? includeEmpty,
  dynamic orderBy,
  Object? Function(String key)? valueOf,
  String Function(String key, String label)? labelOf,
}) async {
  final info = (await api.metadata())?.fields[field];

  if (info == null) {
    return null;
  }

  // A required field has no null to bucket; anything else may.
  final withEmpty = includeEmpty ?? !info.required;
  final choices = info.choices;

  if (choices != null && choices.isNotEmpty) {
    return ChoiceGroupSource(
      field: field,
      choices: choices,
      limit: limit,
      includeEmpty: withEmpty,
      emptyLabel: emptyLabel,
      valueOf: valueOf,
      labelOf: labelOf,
    );
  }

  if (info.type != 'many2one' &&
      info.type != 'many2one_ref' &&
      info.type != 'one2one') {
    return null;
  }

  final target = info.target;

  if (target == null) {
    return null;
  }

  return RelationGroupSource(
    field: field,
    target: GenericApiModel(
      api.basePath,
      modelName: target,
      fetcher: api.fetcher,
    ),
    labelField: labelField ?? await _labelFieldOf(target),
    limit: limit,
    includeEmpty: withEmpty,
    emptyLabel: emptyLabel,
    orderBy: orderBy,
  );
}

Future<String> _labelFieldOf(String model) async {
  if (!hasService<MetadataProvider>()) {
    return 'name';
  }

  final meta = await getService<MetadataProvider>().getMetadata(model);

  return meta == null ? 'name' : resolveLabelField(meta);
}
