/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'data_iterator.dart';

/// The text of a field searching [list], as `v-model` binds it to the search
/// of `useDataIterator`: what is typed goes to [DataIterator.search], and a
/// search changed from elsewhere (« Clear search », the location, a switch of
/// workspace) shows in the field.
class DataSearchController extends TextEditingController {
  DataSearchController([DataIterator<dynamic>? list]) {
    this.list = list;
    addListener(_onText);
  }

  DataIterator<dynamic>? _list;

  /// The list searched, none until it is there: given another one, the field
  /// shows its search.
  DataIterator<dynamic>? get list => _list;

  set list(DataIterator<dynamic>? value) {
    if (value == _list) {
      return;
    }

    _list?.removeListener(_onList);
    _list = value;
    value?.addListener(_onList);
    _onList();
  }

  void _onList() {
    final search = _list?.search;

    if (search != null && search != text) {
      value = TextEditingValue(
        text: search,
        selection: TextSelection.collapsed(offset: search.length),
      );
    }
  }

  void _onText() => _list?.search = text;

  @override
  void dispose() {
    _list?.removeListener(_onList);
    super.dispose();
  }
}
