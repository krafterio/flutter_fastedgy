/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../api/api_collection.dart';
import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';

/// The records a field offers to choose from, the port of `useApiOptions`: a
/// page at a time, searched, and the one already chosen read back by its id.
///
/// Nothing is read before the first [search], the one the field makes when it
/// opens; its input waits for a pause in the typing. The latest search wins
/// over an earlier one answering last.
class ApiOptions<T extends BaseModel<T>> extends ChangeNotifier {
  ApiOptions(
    this.api, {
    this.fields = const [],
    this.filter,
    this.query,
    this.limit = 50,
    this.minSearchLength = 1,
    this.searchFilter,
  }) : _collection = ApiCollection<T>(api, autoRefreshOnChange: false) {
    _collection.addListener(notifyListeners);
  }

  final ApiModel<T> api;

  /// The fields shown, the id read with them.
  final List<String> fields;

  /// The filter always applied: a value, or a [ValueListenable] read at
  /// each read.
  final Object? filter;

  /// More query parameters for each read: a map, or a [ValueListenable] of
  /// one read at each read.
  final Object? query;

  final int limit;

  /// The length under which a text is a keystroke rather than a search.
  final int minSearchLength;

  /// The filter of a text searched.
  final Object? Function(String text)? searchFilter;

  final ApiCollection<T> _collection;
  String _text = '';

  /// The first page did not read: no option to show.
  bool _failed = false;

  /// The next page did not read: no more to offer.
  bool _stopped = false;

  /// Only the latest read says whether the options read.
  int _latest = 0;

  List<T> get items => _failed ? const [] : _collection.items;

  bool get loading => _collection.isLoading || _collection.isLoadingMore;

  bool get hasMore => !_failed && !_stopped && _collection.items.length < total;

  int get total => _collection.total;

  List<String> get _read => {'id', ...fields}.toList();

  Object? _valueOf(Object? source) =>
      source is ValueListenable<Object?> ? source.value : source;

  Object? get _rules {
    final restricted = _valueOf(filter);
    final searched = _text.isNotEmpty ? searchFilter?.call(_text) : null;

    if (restricted != null && searched != null) {
      return [
        '&',
        [restricted, searched],
      ];
    }

    return searched ?? restricted;
  }

  Future<void> _load() async {
    final params = _valueOf(query);
    final run = ++_latest;
    final read = await _collection.readPages(
      1,
      1,
      query: ListQuery(
        size: limit,
        fields: _read,
        filter: _rules,
        params: params is Map<String, String> ? params : null,
      ),
    );

    if (run != _latest) {
      return;
    }

    _failed = !read;
    _stopped = false;
    notifyListeners();
  }

  /// Reads the first page of what [text] matches. A text shorter than
  /// [minSearchLength] is left alone, but an empty one reads the first page.
  Future<void> search([String text = '']) async {
    if (text.isNotEmpty && text.length < minSearchLength) {
      return;
    }

    _text = text;
    await _load();
  }

  /// Reads the next page and adds it to the options.
  Future<void> loadMore() async {
    if (loading || !hasMore) {
      return;
    }

    final run = _latest;
    final read = await _collection.loadMore();

    if (run == _latest) {
      _stopped = !read && _collection.error != null;
      notifyListeners();
    }
  }

  /// Reads the first page again.
  Future<void> refresh() => _load();

  /// Reads back the record [id] with the fields shown, null when it cannot
  /// be read: what a field holding an id shows.
  Future<T?> resolve(Object id) async {
    try {
      return await api.get(id, options: FieldsOptions(fields: _read));
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _collection
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
