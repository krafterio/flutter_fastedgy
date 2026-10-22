/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../container/container.dart';
import '../metadata/default_metadata_provider.dart';
import '../metadata/metadata_provider.dart';
import '../metadata/models.dart';
import '../query/registry.dart';
import '../ui/combo_option.dart';
import 'api_model.dart';
import 'api_record.dart';
import 'base_model.dart';
import 'record_form_controller.dart';

/// The record a form edits, for the [RecordFormField]s below it: each reads
/// its field there and writes it back. Saved by [RecordFormController.save]
/// once [validate] finds nothing to say, a field on its own with [autoSave]
/// (or its own `autoSave`) unless [allowAutoSave] is off. Each save ending is
/// told to [feedback], or to the [RecordFormFeedback] of the container: a
/// toast; a save written, to [onSaved] as well.
class RecordForm<T extends BaseModel<T>> extends StatefulWidget {
  final ApiRecord<T>? record;
  final ApiModel<T>? api;
  final Object? id;

  /// What the record of [api] is read with.
  final dynamic fields;

  /// The record of [api] already held, shown at once.
  final T? seed;

  final RecordFormController<T>? controller;

  /// Whether a field that does not say saves on its own.
  final bool autoSave;

  final bool allowAutoSave;
  final Duration autoSaveDelay;

  /// What a save asked for has to fix first, said in place of saving.
  final RecordFormValidator? validate;

  /// What says the saves of this form, in place of the one of the container.
  final RecordFormFeedback? feedback;

  /// The record as a save wrote it.
  final ValueChanged<T>? onSaved;

  final Widget child;

  /// Edits [record] with a controller of its own, given up with the form:
  /// what waits to be saved on its own is saved then.
  const RecordForm({
    required ApiRecord<T> this.record,
    required this.child,
    super.key,
    this.autoSave = false,
    this.allowAutoSave = true,
    this.autoSaveDelay = const Duration(milliseconds: 600),
    this.validate,
    this.feedback,
    this.onSaved,
  }) : api = null,
       id = null,
       fields = null,
       seed = null,
       controller = null;

  /// Edits the record [id] of [api], read with [fields]: an api of the
  /// application, whose routes are its own, as any other.
  const RecordForm.api({
    required ApiModel<T> this.api,
    required Object this.id,
    required this.child,
    super.key,
    this.fields,
    this.seed,
    this.autoSave = false,
    this.allowAutoSave = true,
    this.autoSaveDelay = const Duration(milliseconds: 600),
    this.validate,
    this.feedback,
    this.onSaved,
  }) : record = null,
       controller = null;

  /// Edits through [controller], held by whoever saves it: a button out of
  /// the form. Its own settings say how it saves.
  const RecordForm.controlled({
    required RecordFormController<T> this.controller,
    required this.child,
    super.key,
    this.feedback,
    this.onSaved,
  }) : record = null,
       api = null,
       id = null,
       fields = null,
       seed = null,
       autoSave = false,
       allowAutoSave = true,
       autoSaveDelay = Duration.zero,
       validate = null;

  /// The controller of the form above [context], if there is one.
  static RecordFormController<dynamic>? controllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_RecordFormScope>()
          ?.controller;

  @override
  State<RecordForm<T>> createState() => _RecordFormState<T>();
}

class _RecordFormState<T extends BaseModel<T>> extends State<RecordForm<T>> {
  late final RecordFormController<T>? _own = _create();

  RecordFormController<T> get _controller => widget.controller ?? _own!;

  Map<String, MetadataField>? _fields;
  StreamSubscription<RecordFormSave>? _saves;

  RecordFormController<T>? _create() {
    final RecordForm(:record, :api, :id) = widget;

    if (record != null) {
      return RecordFormController<T>(
        record,
        autoSave: widget.autoSave,
        allowAutoSave: widget.allowAutoSave,
        autoSaveDelay: widget.autoSaveDelay,
        validate: widget.validate,
      );
    }

    if (api != null && id != null) {
      return RecordFormController<T>.api(
        api,
        id,
        fields: widget.fields,
        seed: widget.seed,
        autoSave: widget.autoSave,
        allowAutoSave: widget.allowAutoSave,
        autoSaveDelay: widget.autoSaveDelay,
        validate: widget.validate,
      );
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _saves = _controller.saves.listen(_tell);
    _fields = _cachedFields();

    if (_fields == null) {
      unawaited(_readFields());
    }
  }

  /// The fields of the model when its metadata were read already: the form
  /// draws at once.
  Map<String, MetadataField>? _cachedFields() {
    final name = _controller.record.api.modelName;
    final provider = hasService<MetadataProvider>()
        ? getService<MetadataProvider>()
        : null;

    return name != null && provider is DefaultMetadataProvider
        ? provider.cachedMetadata(name)?.fields
        : null;
  }

  Future<void> _readFields() async {
    final fields = (await _controller.record.api.metadata())?.fields;

    if (mounted) {
      setState(() => _fields = fields ?? const {});
    }
  }

  void _tell(RecordFormSave save) {
    final feedback =
        widget.feedback ??
        (hasService<RecordFormFeedback>()
            ? getService<RecordFormFeedback>()
            : null);
    final record = _controller.record.value;

    if (!mounted) {
      return;
    }

    feedback?.show(context, save);

    if (save.saved && record != null) {
      widget.onSaved?.call(record);
    }
  }

  @override
  void dispose() {
    unawaited(_saves?.cancel());
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RecordFormScope(
    controller: _controller,
    fields: _fields,
    child: widget.child,
  );
}

/// What a [RecordForm] says once a save ends, written or refused: a service of
/// the container registered by [initializeFastEdgy], silent here. An
/// application registers its own before it starts: a toast, for the saves it
/// wants told.
class RecordFormFeedback {
  const RecordFormFeedback();

  void show(BuildContext context, RecordFormSave save) {}
}

class _RecordFormScope
    extends InheritedNotifier<RecordFormController<dynamic>> {
  final Map<String, MetadataField>? fields;

  const _RecordFormScope({
    required RecordFormController<dynamic> controller,
    required this.fields,
    required super.child,
  }) : super(notifier: controller);

  RecordFormController<dynamic> get controller => notifier!;

  @override
  bool updateShouldNotify(_RecordFormScope oldWidget) =>
      super.updateShouldNotify(oldWidget) || fields != oldWidget.fields;
}

/// How a field of a [RecordForm] is edited, and with what settings: the input
/// registered for its class ([RecordFormInputs.registerInput]). A package of
/// inputs gives its own (a number with its bounds, a choice in cards), an
/// application its own (a picture, an emoji).
@immutable
abstract class FieldInput {
  const FieldInput();
}

/// What the input of a field of a [RecordForm] is given: the form, the field
/// and what the [RecordFormField] says of it.
@immutable
class RecordFormInput {
  final RecordFormController<dynamic> form;
  final MetadataField field;

  /// None when null.
  final String? label;

  final String? placeholder;
  final String? help;

  /// Neither the [RecordFormField] nor the metadata keeps the field from
  /// being changed.
  final bool enabled;

  /// Offered in place of the choices of the metadata.
  final List<ComboOption<Object?>>? options;

  /// The settings of the input, the one asked for.
  final FieldInput? input;

  /// Whether the field saves on its own; null, as the form says.
  final bool? autoSave;

  /// Whether a value set is taken: false leaves the field as it is.
  final bool Function(Object? value)? guard;

  const RecordFormInput({
    required this.form,
    required this.field,
    this.label,
    this.placeholder,
    this.help,
    this.enabled = true,
    this.options,
    this.input,
    this.autoSave,
    this.guard,
  });

  /// What the form holds of the field, its default while it holds none.
  Object? get value => form[field.name] ?? field.defaultValue;

  bool get required => field.required;

  /// Sets the value, unless [guard] refuses it: [typing] while a text is
  /// being typed.
  void set(Object? value, {bool typing = false}) {
    if (guard?.call(value) ?? true) {
      form.set(field.name, value, typing: typing, autoSave: autoSave);
    }
  }

  /// Saves what waits for the typing to pause: the input is left.
  void leave() => unawaited(form.flush());
}

typedef RecordFormInputBuilder = Widget Function(
  BuildContext context,
  RecordFormInput input,
);

/// The inputs of the [RecordForm]s, a service of the container registered by
/// [initializeFastEdgy]: empty here, filled by a package of inputs, then by
/// the application in their place or for a metadata type of its own.
class RecordFormInputs extends FieldRegistry<RecordFormInputBuilder> {
  final _inputs = <Type, RecordFormInputBuilder>{};

  /// Draws with [builder] the fields given an [I] as their input, in place of
  /// the one before.
  void registerInput<I extends FieldInput>(
    Widget Function(BuildContext context, RecordFormInput field, I input)
    builder,
  ) =>
      _inputs[I] = (context, field) =>
          builder(context, field, field.input as I);

  /// What draws the fields given [input], none when nothing is registered for
  /// its class.
  RecordFormInputBuilder? ofInput(FieldInput input) =>
      _inputs[input.runtimeType];
}

/// The field [field] of the record of the [RecordForm] above, edited with
/// [input], or the input [RecordFormInputs] holds for its type. Its label,
/// whether it is required and its default come from the metadata; a read-only
/// field cannot be changed. Nothing shows while the metadata is read, nor for
/// a field no input is registered for.
///
/// [field] is a path in the record: `preferences.compact`, the key `compact`
/// of the JSON field `preferences`, which the metadata do not describe and
/// [type] does.
class RecordFormField extends StatelessWidget {
  final String field;

  /// Left null, the label of the metadata; empty, none.
  final String? label;

  final String? placeholder;
  final String? help;
  final bool enabled;

  /// Offered in place of the choices of the metadata.
  final List<ComboOption<Object?>>? options;

  /// How the field is edited, and with what settings.
  final FieldInput? input;

  /// Whether the field saves on its own; null, as the form says.
  final bool? autoSave;

  /// The metadata type of a field the metadata do not describe: a key of a
  /// JSON field.
  final String? type;

  /// What the field shows while the record holds none, in place of the
  /// default of the metadata.
  final Object? defaultValue;

  /// Whether a value set is taken: false leaves the field as it is (an offer
  /// shown in place of turning a paid option on).
  final bool Function(Object? value)? guard;

  const RecordFormField(
    this.field, {
    super.key,
    this.label,
    this.placeholder,
    this.help,
    this.enabled = true,
    this.options,
    this.input,
    this.autoSave,
    this.type,
    this.defaultValue,
    this.guard,
  });

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RecordFormScope>();

    assert(scope != null, 'A RecordFormField stands under a RecordForm');

    final described = scope?.fields?[field];
    final input = this.input;
    final metadata = scope?.fields == null
        ? null
        : described == null && type == null && input == null
        ? null
        : MetadataField(
            name: field,
            label: described?.label ?? '',
            type: described?.type ?? type ?? '',
            readonly: described?.readonly ?? false,
            required: described?.required ?? false,
            searchable: described?.searchable ?? false,
            extra: described?.extra ?? false,
            filterOperators: described?.filterOperators ?? const [],
            target: described?.target,
            targets: described?.targets,
            inverse: described?.inverse,
            choices: described?.choices,
            defaultValue: defaultValue ?? described?.defaultValue,
            localPlaceholder: described?.localPlaceholder,
          );
    final inputs = hasService<RecordFormInputs>()
        ? getService<RecordFormInputs>()
        : null;
    final builder = metadata == null
        ? null
        : input != null
        ? inputs?.ofInput(input)
        : inputs?.of(metadata);

    if (scope == null || metadata == null || builder == null) {
      return const SizedBox.shrink();
    }

    final label = this.label ?? metadata.label;

    return builder(
      context,
      RecordFormInput(
        form: scope.controller,
        field: metadata,
        label: label.isEmpty ? null : label,
        placeholder: placeholder,
        help: help,
        enabled: enabled && !metadata.readonly && metadata.type != 'computed',
        options: options,
        input: input,
        autoSave: autoSave,
        guard: guard,
      ),
    );
  }
}
