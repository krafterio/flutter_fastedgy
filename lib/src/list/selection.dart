/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

/// The rows chosen in a list, the port of `useSelection`: ids picked one by
/// one, or every record of the filter ([all]) but those unchecked since
/// ([excluded]).
class Selection extends ChangeNotifier {
  Selection({required this.visibleIds, required this.total});

  /// The ids of the rows shown.
  final List<Object?> Function() visibleIds;

  /// How many records the filter holds, every page included.
  final int Function() total;

  Set<Object?> _ids = {};
  bool _all = false;
  Set<Object?> _excluded = {};

  /// The ids chosen one by one.
  List<Object?> get ids => [..._ids];

  set ids(List<Object?> value) {
    _ids = {...value};
    notifyListeners();
  }

  /// Whether every record of the filter is chosen.
  bool get all => _all;

  set all(bool value) {
    _all = value;
    _excluded = {};

    if (value) {
      _ids = {};
    }

    notifyListeners();
  }

  /// The rows unchecked one by one while [all] holds.
  List<Object?> get excluded => [..._excluded];

  int get count => _all ? total() - _excluded.length : _ids.length;

  bool get isAllVisibleSelected {
    final visible = visibleIds();

    return visible.isNotEmpty && visible.every(has);
  }

  /// Whether to offer every record of the filter: the rows shown are all
  /// chosen, and more remain on other pages.
  bool get shouldShowSelectAllButton =>
      isAllVisibleSelected && !_all && total() > visibleIds().length;

  void add(Iterable<Object?> ids) {
    if (_all) {
      _excluded = _excluded.difference({...ids});
    } else {
      _ids = {..._ids, ...ids};
    }

    notifyListeners();
  }

  void remove(Iterable<Object?> ids) {
    if (_all) {
      _excluded = {..._excluded, ...ids};
    } else {
      _ids = _ids.difference({...ids});
    }

    notifyListeners();
  }

  bool has(Object? id) => _all ? !_excluded.contains(id) : _ids.contains(id);

  void clear() {
    if (_ids.isEmpty && !_all && _excluded.isEmpty) {
      return;
    }

    _ids = {};
    _all = false;
    _excluded = {};
    notifyListeners();
  }

  void toggle(Object? id) => has(id) ? remove([id]) : add([id]);

  void selectAllVisible() => add(visibleIds());

  void toggleAll() => all = !_all;
}
