/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../container/container.dart';
import '../fetcher/http_error.dart';
import '../i18n/i18n.dart';
import '../metadata/models.dart';
import '../storage/storage_uploader.dart';
import 'api_model.dart';
import 'api_record.dart';
import 'base_model.dart';
import 'error_formatter.dart';
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

/// What a form has to fix before a save asked for: its message, none when
/// nothing.
typedef RecordFormValidator = String? Function(
  RecordFormController<dynamic> form,
);

/// What a field has to fix before a save asked for, given its value: its
/// message, none when nothing.
typedef RecordFormFieldValidator = String? Function(Object? value);

/// The messages of a refused save: [fields] by the path of the field they
/// are about, [alerts] about none.
typedef RecordFormErrors = ({Map<String, String> fields, List<String> alerts});

/// How a refused save is split between the fields of a form and its alert: a
/// service of the container registered by [initializeFastEdgy], which an
/// application replaces for errors of its own.
///
/// A validation error of the server ([HttpError.validationErrors]) about the
/// body goes to the field its location names (`["body", "preferences",
/// "compact"]` to `preferences.compact`); the others, and any other error, to
/// the alert, as their message.
class RecordFormErrorReader {
  const RecordFormErrorReader();

  RecordFormErrors read(Object error) {
    if (error is RecordFormInvalid) {
      return (fields: const {}, alerts: [error.message]);
    }

    final validation = error is HttpError ? error.validationErrors : null;

    if (validation == null || validation.isEmpty) {
      return (
        fields: const {},
        alerts: [if (error is HttpError) error.message else '$error'],
      );
    }

    final fields = <String, String>{};
    final alerts = <String>[];

    for (final failure in validation) {
      final field = failure.loc.firstOrNull == 'body' ? failure.field : '';

      if (field.isEmpty) {
        alerts.add(failure.msg);
      } else {
        fields.putIfAbsent(field, () => failure.msg);
      }
    }

    return (fields: fields, alerts: alerts);
  }
}

/// Why a save asked for was not sent: what [RecordFormController.validate]
/// said.
@immutable
class RecordFormInvalid implements Exception {
  const RecordFormInvalid(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a save of a [RecordFormController] wrote, or why it could not.
@immutable
class RecordFormSave {
  const RecordFormSave({
    required this.fields,
    required this.auto,
    this.error,
    this.errors = const {},
    this.alerts = const [],
    this.alerted = false,
    this.formatted,
  });

  final Set<String> fields;

  /// Saved on its own as a field was set, not asked for.
  final bool auto;

  final Object? error;

  /// The messages said under the fields shown, by their path.
  final Map<String, String> errors;

  /// The messages about no field shown.
  final List<String> alerts;

  /// Whether an alert of the form shows [alerts] ([RecordFormAlert]): a
  /// feedback says them otherwise.
  final bool alerted;

  /// Everything a refusal says, each field named by its label, for a toast
  /// ([FormattedError.fullMessage]); null once written.
  final FormattedError? formatted;

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
/// that do not say) is saved alone as soon as it is set, with the others set
/// in the same turn, a text once [autoSaveDelay] went by without typing;
/// refused, its value gives way to the one the record holds. [allowAutoSave]
/// off, nothing saves on its own.
///
/// A field is named by its path in the record: `preferences.compact` is the
/// key `compact` of the JSON field `preferences`, written as the whole of
/// `preferences`, the other keys as the record holds them. A [RecordFormFile]
/// is sent to the storage of its field first.
///
/// A save refused says why under the fields shown ([errorOf]), read from the
/// error by the [RecordFormErrorReader] of the container or found by their
/// validator, and the rest in the alert of the form ([alerts]); a field set
/// again lets go of its message.
class RecordFormController<T extends BaseModel<T>> extends ChangeNotifier {
  RecordFormController(
    ApiRecord<T> record, {
    bool autoSave = false,
    bool allowAutoSave = true,
    Duration autoSaveDelay = const Duration(milliseconds: 600),
    RecordFormValidator? validate,
  }) : this._(record, autoSave, allowAutoSave, autoSaveDelay, validate, false);

  /// Edits the record [id] of [api], read with [fields] through a record of
  /// its own, given up with the controller: an api of the application, whose
  /// routes are its own ([ApiModel.getResult], [ApiModel.update]), is read and
  /// written as any other. A [seed] is the record already held, shown at once.
  /// Without [id], a record to create, created by the first save.
  factory RecordFormController.api(
    ApiModel<T> api,
    Object? id, {
    dynamic fields,
    T? seed,
    bool autoSave = false,
    bool allowAutoSave = true,
    Duration autoSaveDelay = const Duration(milliseconds: 600),
    RecordFormValidator? validate,
  }) {
    final record = ApiRecord<T>(api, fields: fields);

    if (id != null) {
      unawaited(record.load(id, seed: seed));
    }

    return RecordFormController._(
      record,
      autoSave,
      allowAutoSave,
      autoSaveDelay,
      validate,
      true,
    );
  }

  RecordFormController._(
    this.record,
    this.autoSave,
    this.allowAutoSave,
    this.autoSaveDelay,
    this.validate,
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

  /// What a save asked for has to fix first: said in place of saving.
  final RecordFormValidator? validate;

  final bool _owns;

  final _edited = <String, Object?>{};

  /// The fields edited that save on their own.
  final _auto = <String>{};

  final _saves = StreamController<RecordFormSave>.broadcast();

  /// The fields shown, how many times each, and the validators they carry.
  final _shown = <String, int>{};
  final _validators = <String, RecordFormFieldValidator>{};
  int _alertViews = 0;

  Map<String, String> _errors = const {};
  List<String> _alerts = const [];
  RecordFormErrors _refusal = (fields: const {}, alerts: const []);
  Map<String, MetadataField>? _read;
  Timer? _typing;
  Future<bool>? _saving;
  Object? _error;
  bool _disposed = false;

  /// The fields of the model: as read, or as the metadata hold them once
  /// read elsewhere when they were not yet as the controller was made.
  Map<String, MetadataField>? get _fields =>
      _read ??= record.api.cachedMetadata()?.fields;

  Future<void> _readFields() async {
    _read = (await record.api.metadata())?.fields;
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

  /// Why the last save refused [field], said under it.
  String? errorOf(String field) => _errors[field];

  /// Why the last save was refused, about no field shown: said by the alert
  /// of the form.
  List<String> get alerts => _alerts;

  /// [field] shows in the form ([RecordFormField]), checked by [validator]
  /// before a save asked for: an error about it is said under it.
  void attach(String field, {RecordFormFieldValidator? validator}) {
    _shown[field] = (_shown[field] ?? 0) + 1;

    if (validator != null) {
      check(field, validator);
    }
  }

  /// [validator] checks [field] before a save asked for, in place of the one
  /// before.
  void check(String field, RecordFormFieldValidator validator) =>
      _validators[field] = validator;

  void detach(String field) {
    final left = (_shown[field] ?? 0) - 1;

    if (left > 0) {
      _shown[field] = left;
    } else {
      _shown.remove(field);
      _validators.remove(field);
    }
  }

  /// An alert of the form shows [alerts] ([RecordFormAlert]).
  void attachAlert() => _alertViews++;

  void detachAlert() => _alertViews--;

  /// Holds [errors] under the fields shown, the others in the alert, named by
  /// their label.
  void _hold(RecordFormErrors errors) {
    final fields = <String, String>{};
    final alerts = [...errors.alerts];

    for (final MapEntry(key: field, value: message) in errors.fields.entries) {
      if (_shown.containsKey(field)) {
        fields[field] = message;
      } else {
        alerts.add(FieldError.about(field, message, _fields).described);
      }
    }

    _refusal = errors;
    _errors = fields;
    _alerts = alerts;
  }

  void _clearErrors() {
    _refusal = (fields: const {}, alerts: const []);
    _errors = const {};
    _alerts = const [];
  }

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

    if (_errors.containsKey(field)) {
      _errors = {..._errors}..remove(field);
    }

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
    _typing = Timer(
      typing ? autoSaveDelay : Duration.zero,
      () => unawaited(_saveAuto()),
    );
  }

  /// Gives up what was edited: every field holds the record's value again.
  void reset() {
    _typing?.cancel();
    _edited.clear();
    _auto.clear();
    _error = null;
    _clearErrors();
    notifyListeners();
  }

  /// Saves at once what waits for the typing to pause.
  Future<bool> flush() =>
      _typing?.isActive ?? false ? _saveAuto() : Future.value(true);

  /// Writes every value that changed once [validate] finds nothing to say:
  /// true once the record holds them. A save asked while one runs waits for
  /// it, then writes what changed meanwhile. Each save asked for is reported
  /// ([saves]), one that had nothing to write included.
  Future<bool> save() async {
    _typing?.cancel();
    _auto.clear();

    final invalid = {
      for (final MapEntry(key: field, value: check) in _validators.entries)
        field: ?check(this[field]),
    };
    final message = validate?.call(this);

    if (invalid.isNotEmpty || message != null) {
      _error = RecordFormInvalid(message ?? invalid.values.first);
      _hold((fields: invalid, alerts: [?message]));
      _notify();
      _report(_refused(const {}, auto: false));

      return false;
    }

    _clearErrors();

    if (_edited.isEmpty && _saving == null) {
      _error = null;
      _notify();
      _report(const RecordFormSave(fields: {}, auto: false));

      return true;
    }

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
    _clearErrors();
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
      final payload = await _payload(sent);

      await (record.id == null
          ? record.create(payload)
          : record.update(payload));
      _forget(sent);
      _report(RecordFormSave(fields: sent.keys.toSet(), auto: auto));

      return true;
    } catch (error) {
      _error = error;
      _hold(
        hasService<RecordFormErrorReader>()
            ? getService<RecordFormErrorReader>().read(error)
            : const RecordFormErrorReader().read(error),
      );

      if (auto) {
        _forget(sent);
      }

      _report(_refused(sent.keys.toSet(), auto: auto));

      return false;
    }
  }

  RecordFormSave _refused(Set<String> fields, {required bool auto}) =>
      RecordFormSave(
        fields: fields,
        auto: auto,
        error: _error,
        errors: _errors,
        alerts: _alerts,
        alerted: _alertViews > 0,
        formatted: FormattedError(
          title: t('Validation error'),
          fieldErrors: [
            for (final MapEntry(key: field, value: message)
                in _refusal.fields.entries)
              FieldError.about(field, message, _fields),
          ],
          messages: _refusal.alerts,
        ),
      );

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
    final model = await record.api.resolveModelName();

    if (model == null) {
      throw StateError('No model names the record of ${record.api.basePath}');
    }

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
