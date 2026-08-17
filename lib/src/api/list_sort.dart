/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// One level of a list ordering.
class SortKey {
  final String field;
  final bool ascending;

  const SortKey(this.field, {this.ascending = true});

  SortKey get flipped => SortKey(field, ascending: !ascending);

  /// One level in the server grammar (`order_by=name:asc,id:desc`), always
  /// explicit: a bare field name would let the server's own default direction
  /// decide, and the arrow drawn in the header would be a guess.
  String get orderBy => '$field:${ascending ? 'asc' : 'desc'}';

  @override
  bool operator ==(Object other) =>
      other is SortKey && other.field == field && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);

  @override
  String toString() => orderBy;
}

/// An ordered list of [SortKey], as a column header produces it: clicking
/// cycles a field through ascending → descending → unsorted, and clicking with
/// a modifier held adds a level instead of replacing the ordering.
///
/// Immutable and Flutter-free: it is state a screen persists (see [encode]) and
/// hands to [ApiCollection.sortBy].
class ListSort {
  final List<SortKey> keys;

  const ListSort([this.keys = const []]);

  static const ListSort empty = ListSort();

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;
  int get length => keys.length;

  /// The level sorting [field], or null when the ordering ignores it.
  SortKey? keyFor(String field) {
    for (final key in keys) {
      if (key.field == field) {
        return key;
      }
    }

    return null;
  }

  /// 1-based priority of [field] in the ordering, null when unsorted. A header
  /// showing it is a caller's decision: with a single key the rank carries no
  /// information and is left out.
  int? rankOf(String field) {
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].field == field) {
        return i + 1;
      }
    }

    return null;
  }

  /// The ordering after a click on [field]'s header.
  ///
  /// A plain click leaves a single level, and *advances* the clicked field's
  /// phase instead of restarting it: on `[b asc, a asc]`, clicking `a` gives
  /// `[a desc]`. Restarting at ascending would cost one more click to reach the
  /// order the user was already asking for.
  ///
  /// An [additive] click appends a level, flips an existing one **in place**
  /// (its rank does not move — a modifier click is never a promotion), and on
  /// the third phase removes it, the levels below moving up one rank.
  ListSort cycle(String field, {bool additive = false}) {
    final current = keyFor(field);

    if (!additive) {
      if (current == null) {
        return ListSort([SortKey(field)]);
      }

      return current.ascending ? ListSort([current.flipped]) : empty;
    }

    if (current == null) {
      return ListSort([...keys, SortKey(field)]);
    }

    if (current.ascending) {
      return ListSort([
        for (final key in keys) key.field == field ? key.flipped : key,
      ]);
    }

    return ListSort([
      for (final key in keys)
        if (key.field != field) key,
    ]);
  }

  /// The `order_by` value for a list request. Empty when nothing is sorted,
  /// which is how the server is told to apply its own `default_order_by`.
  List<String> toOrderBy() => [for (final key in keys) key.orderBy];

  /// Compact form for a URL (`status,-name`): a descending level is prefixed
  /// with `-`. Half the length of the server grammar, needs no escaping, and
  /// reads at a glance in a shared link.
  String encode() =>
      [for (final key in keys) key.ascending ? key.field : '-${key.field}']
          .join(',');

  /// Reads back what [encode] wrote. Tolerant by contract — a URL is user
  /// input: it never throws, skips blanks, keeps the first mention of a
  /// repeated field, and drops any field [allow] refuses (an ordering on a
  /// column this list does not have would make the server answer 400).
  static ListSort decode(String? raw, {bool Function(String field)? allow}) {
    if (raw == null || raw.trim().isEmpty) {
      return empty;
    }

    final keys = <SortKey>[];
    final seen = <String>{};

    for (final part in raw.split(',')) {
      final token = part.trim();

      if (token.isEmpty) {
        continue;
      }

      final ascending = !token.startsWith('-');
      final field = (ascending ? token : token.substring(1)).trim();

      if (field.isEmpty || (allow != null && !allow(field))) {
        continue;
      }

      if (seen.add(field)) {
        keys.add(SortKey(field, ascending: ascending));
      }
    }

    return ListSort(keys);
  }

  @override
  bool operator ==(Object other) {
    if (other is! ListSort || other.keys.length != keys.length) {
      return false;
    }

    for (var i = 0; i < keys.length; i++) {
      if (other.keys[i] != keys[i]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode => Object.hashAll(keys);

  @override
  String toString() => 'ListSort(${encode()})';
}
