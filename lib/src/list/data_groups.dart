/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_collection.dart';
import '../api/base_model.dart';
import '../api/group_source.dart';

/// Where the group of the rows with no value stands on the axis.
enum EmptyGroup { last, first, none }

/// A group of a grouped [DataIterator]: what the axis says of it, its rows and
/// their pages.
class DataGroup<T extends BaseModel<T>> {
  const DataGroup(this.group, this._rows, this.filter);

  final ListGroup group;
  final ApiCollection<T> _rows;

  /// The filter its rows are read with: the one of the list, its predicate,
  /// and the rule the list adds for it.
  final Object? filter;

  String get key => group.key;

  String get label => group.label;

  String? get color => group.color;

  Object? get value => group.value;

  /// The rule the group stands for.
  List<Object?> get predicate => group.predicate;

  bool get isEmptyBucket => group.isEmptyBucket;

  /// The record of a group of a relation, as the axis read it.
  Map<String, dynamic>? get record => group.record;

  List<T> get items => _rows.items;

  int get total => _rows.total;

  int get page => _rows.page;

  int get totalPages => _rows.totalPages;

  bool get hasMore => _rows.hasNextPage;

  bool get loading => _rows.isLoading || _rows.isLoadingMore;

  Object? get error => _rows.error;

  Future<bool> setPage(int page) => _rows.setPage(page);

  /// Adds the next page to its rows.
  Future<bool> loadMore() => _rows.loadMore();
}
