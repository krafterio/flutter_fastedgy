/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../metadata/models.dart';
import 'api_record.dart';
import 'base_model.dart';
import 'record_values.dart';

/// The values a form edits of the record [record] holds: a field nobody edits
/// follows the record as it is read again, an edited one keeps what was typed
/// until it is saved.
///
/// [save] writes what changed alone through [record] ([ApiRecord.update]):
/// shown at once on every holder of the record, put back when refused. With
/// [autoSave], a value is saved as soon as it is set, a text once
/// [autoSaveDelay] went by without typing; a refused value gives way to the
/// one the record holds. Without it, a refused value stays, for the form to
/// say what failed ([error]) and be saved again.
class RecordFormController<T extends BaseModel<T>> extends ChangeNotifier {
  RecordFormController(
    this.record, {
    this.autoSave = false,
    this.autoSaveDelay = const Duration(milliseconds: 600),
  }) {
    record.addListener(notifyListeners);
    unawaited(_readFields());
  }

  final ApiRecord<T> record;
  final bool autoSave;
  final Duration autoSaveDelay;

  final _edited = <String, Object?>{};
  Map<String, MetadataField>? _fields;
  Timer? _typing;
  Future<bool>? _saving;
  Object? _error;
  bool _disposed = false;

  Future<void> _readFields() async {
    _fields = (await record.api.metadata())?.fields;
  }

  /// What [field] holds in the form: the value edited, the record's otherwise.
  Object? operator [](String field) =>
      _edited.containsKey(field) ? _edited[field] : record.value?.data[field];

  /// Some value differs from the record's.
  bool get dirty => _edited.isNotEmpty;

  /// The values that differ from the record's, as the form holds them.
  Map<String, Object?> get changes => Map.unmodifiable(_edited);

  bool get saving => _saving != null;

  /// Why the last save was refused, until the next one.
  Object? get error => _error;

  bool _holds(String field, Object? value) {
    final metadata = _fields?[field];

    return sameValue(
      sentValue(metadata, value),
      sentValue(metadata, record.value?.data[field]),
    );
  }

  /// Sets [field] to [value], held as the record holds it (a record as its
  /// fields, a date as its day): [typing] while a text is being typed, saved
  /// with [autoSave] once the typing pauses rather than at once.
  void set(String field, Object? value, {bool typing = false}) {
    final shown = shownValue(_fields?[field], value);

    if (_holds(field, shown)) {
      _edited.remove(field);
    } else {
      _edited[field] = shown;
    }

    notifyListeners();

    if (!autoSave) {
      return;
    }

    _typing?.cancel();

    if (typing) {
      _typing = Timer(autoSaveDelay, () => unawaited(save()));
    } else {
      unawaited(save());
    }
  }

  /// Gives up what was edited: every field holds the record's value again.
  void reset() {
    _typing?.cancel();
    _edited.clear();
    _error = null;
    notifyListeners();
  }

  /// Saves at once what waits for the typing to pause.
  Future<bool> flush() =>
      _typing?.isActive ?? false ? save() : Future.value(true);

  /// Writes what changed: true once the record holds it. A save asked while
  /// one runs waits for it, then writes what changed meanwhile.
  Future<bool> save() async {
    _typing?.cancel();

    final running = _saving;

    if (running != null) {
      await running;

      return save();
    }

    if (_edited.isEmpty) {
      return true;
    }

    final sent = Map<String, Object?>.of(_edited);
    final saving = _write(sent);

    _saving = saving;
    _error = null;
    _notify();

    try {
      return await saving;
    } finally {
      _saving = null;
      _notify();
    }
  }

  Future<bool> _write(Map<String, Object?> sent) async {
    try {
      await record.update(sent);
      _forget(sent);

      return true;
    } catch (error) {
      _error = error;

      if (autoSave) {
        _forget(sent);
      }

      return false;
    }
  }

  /// Takes out of the edits what [sent] wrote, unless typed again meanwhile.
  void _forget(Map<String, Object?> sent) {
    for (final MapEntry(:key, :value) in sent.entries) {
      if (_edited.containsKey(key) && sameValue(_edited[key], value)) {
        _edited.remove(key);
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Leaving with [autoSave], what waits for the typing to pause is saved.
  @override
  void dispose() {
    _disposed = true;

    if (autoSave && (_typing?.isActive ?? false)) {
      unawaited(save());
    }

    _typing?.cancel();
    record.removeListener(notifyListeners);
    super.dispose();
  }
}
