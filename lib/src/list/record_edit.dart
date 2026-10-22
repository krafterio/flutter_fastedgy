/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

import '../api/api_query.dart';
import '../api/base_model.dart';
import '../api/error_formatter.dart';
import '../api/record_values.dart';
import '../fetcher/http_error.dart';
import 'data_iterator.dart';

/// Writes [value] of [field] of [item] in place of the route of its model:
/// the service of a model that normalizes what it receives. Gives the row
/// saved, null to keep the one shown.
typedef RecordWrite<T> = Future<T?> Function(
  T item,
  String field,
  Object? value,
);

/// The cells of a list edited in place, the port of `useRecordEdit`: a value
/// shows at once, then is written, the answer taking the place of the row,
/// the echo left unread. A refusal puts the value back and keeps the message
/// of the server on its cell, or on its row when it names no field.
class RecordEdit<T extends BaseModel<T>> extends ChangeNotifier {
  RecordEdit(this.list, {this.write, this.onError});

  final DataIterator<T> list;

  /// Writes a value in place of the route of the model.
  final RecordWrite<T>? write;

  /// Told of each refusal once its messages are kept: a toast, for one.
  final void Function(Object error)? onError;

  final _saving = <(Object?, String)>{};
  final _errors = <Object?, Map<String, String>>{};
  final _rowErrors = <Object?, String>{};
  bool _creating = false;

  /// Whether [field] of [item] is being written; of the draft row for null.
  bool isSaving(T? item, String field) =>
      item == null ? _creating : _saving.contains((item.id, field));

  /// The message of the server for [field] of [item], of the draft row for
  /// null.
  String? errorOf(T? item, String field) => _errors[item?.id]?[field];

  /// The message of the server for [item] that names no field.
  String? rowErrorOf(T? item) => _rowErrors[item?.id];

  /// Shows [value] in [field] of [item] at once, then writes it: a relation
  /// as its id, several as their ids, a date as its day, an instant in UTC.
  /// Gives the row saved, null when it was refused. A value the row already
  /// holds writes nothing.
  Future<T?> edit(T item, String field, Object? value) async {
    final api = list.api;
    final meta = (await api.metadata())?.fields[field];
    final shown = shownValue(meta, value);
    final sent = sentValue(meta, shown);
    final id = item.id;

    if (sameValue(sent, sentValue(meta, shownValue(meta, item.data[field])))) {
      return item;
    }

    final key = (id, field);

    _saving.add(key);
    _errors[id]?.remove(field);
    _rowErrors.remove(id);
    list.upsertLocal(api.fromJson({...item.data, field: shown}));
    notifyListeners();

    try {
      final write = this.write;
      final saved = await list.writing(
        () => write != null
            ? write(item, field, sent)
            : api.update(
                id!,
                payloadOf<T>(api, {field: sent}),
                options: FieldsOptions(fields: list.fields),
              ),
      );

      if (saved != null) {
        list.upsertLocal(saved);
      }

      return saved ?? list.byId(id);
    } catch (error) {
      final current = list.byId(id) ?? item;

      list.upsertLocal(
        api.fromJson({...current.data, field: item.data[field]}),
      );
      _keep(id, error);
      onError?.call(error);

      return null;
    } finally {
      _saving.remove(key);
      notifyListeners();
    }
  }

  /// Creates the record of the draft row from [values], written as [edit]
  /// writes them, and adds it at the start of the list. Gives it, or null
  /// when it was refused, the messages of the server kept on the draft.
  Future<T?> create(Map<String, Object?> values) async {
    final api = list.api;
    final fields = (await api.metadata())?.fields;

    _creating = true;
    _errors.remove(null);
    _rowErrors.remove(null);
    notifyListeners();

    try {
      final created = await list.writing(
        () => api.create(
          payloadOf<T>(api, {
            for (final MapEntry(:key, :value) in values.entries)
              key: sentValue(fields?[key], shownValue(fields?[key], value)),
          }),
          options: FieldsOptions(fields: list.fields),
        ),
      );

      list.upsertLocal(created, prepend: true);

      return created;
    } catch (error) {
      _keep(null, error);
      onError?.call(error);

      return null;
    } finally {
      _creating = false;
      notifyListeners();
    }
  }

  /// Keeps what the server said of [id]: by field, and for the whole row
  /// what it says about none.
  void _keep(Object? id, Object error) {
    final formatted = error is HttpError
        ? formatApiError(error.data, defaultTitle: error.message)
        : formatApiError(null);

    if (formatted.hasFieldErrors) {
      (_errors[id] ??= {}).addAll({
        for (final one in formatted.fieldErrors) one.field: one.message,
      });
    }

    if (!formatted.hasFieldErrors || formatted.messages.isNotEmpty) {
      _rowErrors[id] = formatted.messages.isEmpty
          ? formatted.title
          : formatted.messages.join('\n');
    }
  }
}
