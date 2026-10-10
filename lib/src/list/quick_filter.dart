/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/widgets.dart';

/// A filter of one gesture beside the filter button of a list: a tab, a chip
/// « Late », a choice of member. Its value lives in the `quick` of the list
/// and in the `qf` key of the URL, so it is a JSON value.
class QuickFilter<V> {
  QuickFilter({
    required this.name,
    required Object? Function(V? value) filter,
    this.defaultValue,
    Widget Function(BuildContext context, V? value, ValueChanged<V?> onChanged)?
    builder,
  }) : _rule = ((value) => filter(value as V?)),
       _control = builder == null
           ? null
           : ((context, value, onChanged) =>
                 builder(context, value as V?, onChanged));

  /// Its key in the `quick` of the list and in `qf`.
  final String name;

  /// Its value while the URL says nothing of it.
  final V? defaultValue;

  final Object? Function(Object? value) _rule;
  final Widget Function(BuildContext, Object?, ValueChanged<Object?>)? _control;

  /// The rule [value] stands for, null for none.
  Object? ruleOf(Object? value) => _rule(value);

  /// Whether it draws its own control.
  bool get hasControl => _control != null;

  /// Its control, drawing [value] and telling [onChanged] what it changes to;
  /// null when it draws none.
  Widget? buildControl(
    BuildContext context,
    Object? value,
    ValueChanged<Object?> onChanged,
  ) => _control?.call(context, value, onChanged);
}

String _json(Object? value) => jsonEncode(value, toEncodable: (_) => null);

/// Reads the quick filters of a URL (`qf`), each at its default unless the
/// URL says otherwise, every one of them at its default when it does not
/// read.
Map<String, Object?> readQuickFilters(
  String? raw,
  List<QuickFilter<Object?>> definitions,
) {
  Object? given;

  try {
    given = raw == null || raw.isEmpty ? null : jsonDecode(raw);
  } on FormatException {
    given = null;
  }

  final read = given is Map ? given : const {};

  return {
    for (final one in definitions)
      one.name: read.containsKey(one.name) ? read[one.name] : one.defaultValue,
  };
}

/// What a URL keeps of the quick filters: those away from their default, or
/// null when none is.
String? writeQuickFilters(
  Map<String, Object?> values,
  List<QuickFilter<Object?>> definitions,
) {
  final moved = {
    for (final one in definitions)
      if (_json(values[one.name]) != _json(one.defaultValue))
        one.name: values[one.name],
  };

  return moved.isEmpty ? null : jsonEncode(moved);
}
