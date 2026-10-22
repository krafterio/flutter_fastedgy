/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../container/container.dart';
import '../metadata/models.dart';
import '../storage/storage_uploader.dart';
import 'api_model.dart';
import 'api_record.dart';
import 'base_model.dart';
import 'record_values.dart';

/// A file a field of a form is given: sent to the storage of that field of
/// the record as the form is saved, its path then written in the field.
@immutable
class RecordFormFile {
  const RecordFormFile({
    required Uint8List this.bytes,
    required this.name,
    this.mimeType,
  });

  /// The file the field holds taken out: deleted from the storage as the form
  /// is saved, the field emptied.
  const RecordFormFile.removed() : bytes = null, name = '', mimeType = null;

  final Uint8List? bytes;
  final String name;

  /// Read from [name] when null.
  final String? mimeType;

  bool get removed => bytes == null;
}

/// What a save of a [RecordFormController] wrote, or why it could not.
@immutable
class RecordFormSave {
  const RecordFormSave({required this.fields, required this.auto, this.error});

  final Set<String> fields;

  /// Saved on its own as a field was set, not asked for.
  final bool auto;

  final Object? error;

  bool get saved => error == null;
}

/// The values a form edits of the record [record] holds: a field nobody edits
/// follows the record as it is read again, an edited one keeps what was typed
/// until it is saved.
///
/// [save] writes what changed alone through [record] ([ApiRecord.update]):
/// shown at once on every holder of the record, put back when refused. A
/// refused value stays, for the form to say what failed ([error]) and be
/// saved again.
///
/// A field set to save on its own ([set] `autoSave`, [autoSave] for those
/// that do not say) is saved alone as soon as it is set, a text once
/// [autoSaveDelay] went by without typing; refused, its value gives way to the
/// one the record holds. [allowAutoSave] off, nothing saves on its own.
///
/// A field is named by its path in the record: `preferences.compact` is the
/// key `compact` of the JSON field `preferences`, written as the whole of
/// `preferences`, the other keys as the record holds them. A [RecordFormFile]
/// is sent to the storage of its field first.
class RecordFormController<T extends BaseModel<T>> extends ChangeNotifier {
  RecordFormController(
    ApiRecord<T> record, {
    bool autoSave = false,
    bool allowAutoSave = true,
    Duration autoSaveDelay = const Duration(milliseconds: 600),
  }) : this._(record, autoSave, allowAutoSave, autoSaveDelay, false);

  /// Edits the record [id] of [api], read with [fields] through a record of
  /// its own, given up with the controller: an api of the application, whose
  /// routes are its own ([ApiModel.getResult], [ApiModel.update]), is read and
  /// written as any other.
  factory RecordFormController.api(
    ApiModel<T> api,
    Object id, {
    dynamic fields,
    bool autoSave = false,
    bool allowAutoSave = true,
    Duration autoSaveDelay = const Duration(milliseconds: 600),
  }) {
    final record = ApiRecord<T>(api, fields: fields);

    unawaited(record.load(id));

    return RecordFormController._(
      record,
      autoSave,
      allowAutoSave,
      autoSaveDelay,
      true,
    );
  }

  RecordFormController._(
    this.record,
    this.autoSave,
    this.allowAutoSave,
    this.autoSaveDelay,
    this._owns,
  ) {
    record.addListener(notifyListeners);
    unawaited(_readFields());
  }

  final ApiRecord<T> record;

  /// Whether a field that does not say saves on its own.
  final bool autoSave;

  final bool allowAutoSave;
  final Duration autoSaveDelay;
  final bool _owns;

  final _edited = <String, Object?>{};

  /// The fields edited that save on their own.
  final _auto = <String>{};

  final _saves = StreamController<RecordFormSave>.broadcast();
  Map<String, MetadataField>? _fields;
  Timer? _typing;
  Future<bool>? _saving;
  Object? _error;
  bool _disposed = false;

  Future<void> _readFields() async {
    _fields = (await record.api.metadata())?.fields;
  }

  /// What [field] holds in the form: the value edited, the record's otherwise.
  Object? operator [](String field) => _edited.containsKey(field)
      ? _edited[field]
      : _at(record.value?.data, field);

  /// Some value differs from the record's.
  bool get dirty => _edited.isNotEmpty;

  /// The values that differ from the record's, as the form holds them.
  Map<String, Object?> get changes => Map.unmodifiable(_edited);

  bool get saving => _saving != null;

  /// Why the last save was refused, until the next one.
  Object? get error => _error;

  /// Each save as it ends, written or refused.
  Stream<RecordFormSave> get saves => _saves.stream;

  bool _holds(String field, Object? value) {
    if (value is RecordFormFile) {
      return value.removed && _at(record.value?.data, field) == null;
    }

    final metadata = _fields?[field];

    return sameValue(
      sentValue(metadata, value),
      sentValue(metadata, _at(record.value?.data, field)),
    );
  }

  /// Sets [field] to [value], held as the record holds it (a record as its
  /// fields, a date as its day): [typing] while a text is being typed. Saved
  /// on its own with [autoSave], or the form's [RecordFormController.autoSave]
  /// when null: at once, or once the typing pauses.
  void set(String field, Object? value, {bool typing = false, bool? autoSave}) {
    final shown = shownValue(_fields?[field], value);

    if (_holds(field, shown)) {
      _edited.remove(field);
      _auto.remove(field);
    } else {
      _edited[field] = shown;
    }

    notifyListeners();

    if (!allowAutoSave ||
        !(autoSave ?? this.autoSave) ||
        !_edited.containsKey(field)) {
      return;
    }

    _auto.add(field);
    _typing?.cancel();

    if (typing) {
      _typing = Timer(autoSaveDelay, () => unawaited(_saveAuto()));
    } else {
      unawaited(_saveAuto());
    }
  }

  /// Gives up what was edited: every field holds the record's value again.
  void reset() {
    _typing?.cancel();
    _edited.clear();
    _auto.clear();
    _error = null;
    notifyListeners();
  }

  /// Saves at once what waits for the typing to pause.
  Future<bool> flush() =>
      _typing?.isActive ?? false ? _saveAuto() : Future.value(true);

  /// Writes every value that changed: true once the record holds them. A save
  /// asked while one runs waits for it, then writes what changed meanwhile.
  Future<bool> save() {
    _typing?.cancel();
    _auto.clear();

    return _save(() => _edited.keys.toSet(), auto: false);
  }

  Future<bool> _saveAuto() {
    _typing?.cancel();

    final fields = {..._auto};

    _auto.clear();

    return _save(() => fields, auto: true);
  }

  Future<bool> _save(
    Set<String> Function() fields, {
    required bool auto,
  }) async {
    final running = _saving;

    if (running != null) {
      await running;

      return _save(fields, auto: auto);
    }

    final sent = {
      for (final field in fields())
        if (_edited.containsKey(field)) field: _edited[field],
    };

    if (sent.isEmpty) {
      return true;
    }

    final saving = _write(sent, auto: auto);

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

  Future<bool> _write(Map<String, Object?> sent, {required bool auto}) async {
    try {
      await record.update(await _payload(sent));
      _forget(sent);
      _report(RecordFormSave(fields: sent.keys.toSet(), auto: auto));

      return true;
    } catch (error) {
      _error = error;

      if (auto) {
        _forget(sent);
      }

      _report(
        RecordFormSave(fields: sent.keys.toSet(), auto: auto, error: error),
      );

      return false;
    }
  }

  /// [sent] as the record takes it: a file as its path once stored, the key
  /// of a JSON field in the whole of that field.
  Future<Map<String, Object?>> _payload(Map<String, Object?> sent) async {
    final values = <String, Object?>{};

    for (final MapEntry(:key, :value) in sent.entries) {
      final written = value is RecordFormFile
          ? await _store(key, value)
          : value;
      final [root, ...path] = key.split('.');

      if (path.isEmpty) {
        values[root] = written;

        continue;
      }

      final base = values[root] ?? record.value?.data[root];

      values[root] = _withAt(base is Map ? base : const {}, path, written);
    }

    return values;
  }

  Future<String?> _store(String field, RecordFormFile file) async {
    final uploader = getService<StorageUploader>();
    final model = await record.api.resolveModelName() ?? record.api.basePath;
    final id = int.parse('${record.id}');
    final bytes = file.bytes;

    if (bytes == null) {
      if (_at(record.value?.data, field) != null) {
        await uploader.deleteModelField(
          model: model,
          modelId: id,
          field: field,
        );
      }

      return null;
    }

    return (await uploader.uploadModelFieldFromBytes(
      model: model,
      modelId: id,
      field: field,
      bytes: bytes,
      fileName: file.name,
      mimeType: file.mimeType,
    )).path;
  }

  /// Takes out of the edits what [sent] wrote, unless set again meanwhile.
  void _forget(Map<String, Object?> sent) {
    for (final MapEntry(:key, :value) in sent.entries) {
      final edited = _edited[key];

      if (_edited.containsKey(key) &&
          (identical(edited, value) ||
              (edited is! RecordFormFile && sameValue(edited, value)))) {
        _edited.remove(key);
      }
    }
  }

  void _report(RecordFormSave save) {
    if (!_saves.isClosed) {
      _saves.add(save);
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Leaving, what waits for the typing to pause to save on its own is saved.
  @override
  void dispose() {
    _disposed = true;

    final pending = _typing?.isActive ?? false ? _saveAuto() : _saving;

    _typing?.cancel();
    record.removeListener(notifyListeners);
    unawaited(_saves.close());

    if (_owns) {
      unawaited(
        pending?.whenComplete(record.dispose) ?? Future.sync(record.dispose),
      );
    }

    super.dispose();
  }
}

/// What [data] holds at [path], keys of nested maps joined by dots.
Object? _at(Object? data, String path) {
  Object? value = data;

  for (final key in path.split('.')) {
    value = value is Map ? value[key] : null;
  }

  return value;
}

/// [map] with [value] at [path], the maps on the way copied.
Map<String, Object?> _withAt(
  Map<dynamic, dynamic> map,
  List<String> path,
  Object? value,
) {
  final [key, ...rest] = path;
  final copy = {
    for (final MapEntry(:key, :value) in map.entries) '$key': value,
  };
  final inner = copy[key];

  copy[key] = rest.isEmpty
      ? value
      : _withAt(inner is Map ? inner : const {}, rest, value);

  return copy;
}
