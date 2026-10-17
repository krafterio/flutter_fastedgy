/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';
import 'record_values.dart';

/// What a write of this process shows before the server answers, for every
/// holder of the record to show it too: the [values] written, as a row holds
/// them, or the record gone when [deleted]. A refusal sends back the values
/// the record held before. [source] is the holder that wrote, which shows them
/// already.
class ResourcePatchedEvent {
  const ResourcePatchedEvent(
    this.basePath, {
    required this.id,
    this.model,
    this.values = const {},
    this.deleted = false,
    this.source,
  });

  final String? basePath;
  final String? model;
  final Object? id;
  final Map<String, Object?> values;
  final bool deleted;
  final Object? source;

  /// Whether this event is about what [api] holds, as
  /// [ResourceChangedEvent.isAbout] tells.
  bool isAbout(ApiModel<dynamic> api) => model != null
      ? model == api.eventModelName
      : basePath == api.resolvedBasePath;
}

/// The writes of a holder, shown before the server answers.
///
/// [updateItem] shows its values at once, on every holder of the record, then
/// writes them; the record the server answers takes their place, and a refusal
/// puts back what was shown before and is thrown. [deleteItem] takes the record
/// out at once, everywhere, and puts it back when refused. [createItem] adds
/// the record the server answers. None reads the echo of its own write. They go
/// through [api] as any write does, buffered when it is offline.
mixin LocalWrites<T extends BaseModel<T>> {
  ApiModel<T> get api;

  /// The fields a write asks back: those the holder reads.
  dynamic get writeFields;

  T? byId(Object? id);

  bool upsertLocal(T item, {bool prepend = false});

  /// Takes the record [id] out, giving what puts it back where it was; null
  /// when the holder does not take it out.
  VoidCallback? takeLocal(Object? id);

  /// Runs [write], whose echo the holder does not read.
  Future<R> writing<R>(Future<R> Function() write);

  StreamSubscription<ResourcePatchedEvent>? _patches;

  FieldsOptions? get _options =>
      writeFields == null ? null : FieldsOptions(fields: writeFields);

  /// Shows from now on what the writes of the other holders show.
  @protected
  void followPatches() {
    if (hasService<Bus>()) {
      _patches = getService<Bus>().on<ResourcePatchedEvent>().listen(
        _onPatched,
      );
    }
  }

  @protected
  void stopFollowingPatches() => unawaited(_patches?.cancel());

  void _onPatched(ResourcePatchedEvent event) {
    if (identical(event.source, this) || !event.isAbout(api)) {
      return;
    }

    if (event.deleted) {
      takeLocal(event.id);

      return;
    }

    final current = byId(event.id);

    if (current != null) {
      upsertLocal(api.fromJson({...current.data, ...event.values}));
    }
  }

  void _patch(Object? id, Map<String, Object?> values, {bool deleted = false}) {
    if (hasService<Bus>()) {
      getService<Bus>().fire(
        ResourcePatchedEvent(
          api.resolvedBasePath,
          id: id,
          model: api.eventModelName,
          values: values,
          deleted: deleted,
          source: this,
        ),
      );
    }
  }

  /// [values] on the record of [item] at once, here and on every holder of it.
  void _show(T item, Map<String, Object?> values) {
    final current = byId(item.id) ?? item;

    upsertLocal(api.fromJson({...current.data, ...values}));
    _patch(item.id, values);
  }

  /// Shows [values] in the record of [item] at once, then writes them: a
  /// relation as its id, several as their ids, a date as its day, an instant
  /// in UTC. Gives the record saved; a refusal puts back what the record held
  /// before and is thrown.
  Future<T> updateItem(T item, Map<String, Object?> values) async {
    final saved = await updateItemWith(
      item,
      values,
      (sent) =>
          api.update(item.id!, payloadOf<T>(api, sent), options: _options),
    );
    final merged = api.fromJson({
      ...(byId(item.id) ?? item).data,
      ...saved.data,
    });

    upsertLocal(merged);

    return merged;
  }

  /// Shows [values] in the record of [item] at once, here and on every holder
  /// of it, while [write] sends them as the server takes them: a route of its
  /// own, an action of the model. A refusal puts back what the record held
  /// before and is thrown.
  Future<R> updateItemWith<R>(
    T item,
    Map<String, Object?> values,
    Future<R> Function(Map<String, Object?> sent) write,
  ) async {
    final fields = (await api.metadata())?.fields;
    final before = byId(item.id) ?? item;
    final shown = {
      for (final MapEntry(:key, :value) in values.entries)
        key: shownValue(fields?[key], value),
    };
    final previous = {for (final key in values.keys) key: before.data[key]};

    _show(item, shown);

    try {
      return await writing(
        () => write({
          for (final MapEntry(:key, :value) in shown.entries)
            key: sentValue(fields?[key], value),
        }),
      );
    } catch (_) {
      _show(item, previous);
      rethrow;
    }
  }

  /// Takes the record of [item] out at once, here and on every holder of it,
  /// then deletes it; a refusal puts it back and is thrown.
  Future<void> deleteItem(T item) =>
      deleteItemWith(item, () => api.delete(item.id!));

  /// Takes the record of [item] out at once, here and on every holder of it,
  /// while [write] deletes it: a route of its own. A refusal puts it back and
  /// is thrown.
  Future<R> deleteItemWith<R>(T item, Future<R> Function() write) async {
    final id = item.id;
    final restore = takeLocal(id);

    _patch(id, const {}, deleted: true);

    try {
      return await writing(write);
    } catch (_) {
      restore?.call();

      // The other holders took it out as well: they read it again.
      if (hasService<Bus>()) {
        getService<Bus>().fire(
          ResourceChangedEvent(
            api.resolvedBasePath,
            model: api.modelName,
            id: id,
          ),
        );
      }

      rethrow;
    }
  }

  /// Creates a record of [values], written as [updateItem] writes them, and
  /// adds the one the server answers over them, at the start when [prepend]
  /// is set.
  Future<T> createItem(
    Map<String, Object?> values, {
    bool prepend = false,
  }) async {
    final fields = (await api.metadata())?.fields;
    final shown = {
      for (final MapEntry(:key, :value) in values.entries)
        key: shownValue(fields?[key], value),
    };
    final created = await writing(
      () => api.create(
        payloadOf<T>(api, {
          for (final MapEntry(:key, :value) in shown.entries)
            key: sentValue(fields?[key], value),
        }),
        options: _options,
      ),
    );
    final merged = api.fromJson({...shown, ...created.data});

    upsertLocal(merged, prepend: prepend);

    return merged;
  }
}
