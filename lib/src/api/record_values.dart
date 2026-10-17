/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import '../metadata/models.dart';
import '../query/catalog.dart';
import '../query/dates.dart';
import '../query/query_fields.dart';
import 'api_model.dart';
import 'base_model.dart';

/// [value] as a row holds it: a record as its fields, a date as its day, an
/// instant in UTC.
Object? shownValue(MetadataField? field, Object? value) => switch (value) {
  BaseModel<dynamic>() => value.data,
  List<Object?>() => [for (final one in value) shownValue(field, one)],
  DateTime() when field?.type == 'date' => dayOf(value.toIso8601String()),
  DateTime() => value.toUtc().toIso8601String(),
  _ => value,
};

/// What a row holds of [field] as the server takes it: a relation as its id,
/// or their ids.
Object? sentValue(MetadataField? field, Object? shown) {
  Object? idOf(Object? one) => one is Map ? one['id'] : one;

  return switch (relationKindOf(field)) {
    FieldKind.single => idOf(shown),
    FieldKind.multiple => [
      for (final one in shown as List? ?? const []) idOf(one),
    ],
    _ => shown,
  };
}

/// Whether [a] and [b] say the same once written.
bool sameValue(Object? a, Object? b) => _json(a) == _json(b);

String _json(Object? value) => jsonEncode(value, toEncodable: (_) => null);

/// A payload holding [values] as they are: built from them, a model reads a
/// text that looks like an instant as a local date.
T payloadOf<T extends BaseModel<T>>(
  ApiModel<T> api,
  Map<String, Object?> values,
) {
  final payload = api.fromJson(const {});

  for (final MapEntry(:key, :value) in values.entries) {
    payload.setField(key, value);
  }

  return payload;
}
