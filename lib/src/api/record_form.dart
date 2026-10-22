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
/// its field there and writes it back. Saved by [RecordFormController.save],
/// a field on its own with [autoSave] (or its own `autoSave`) unless
/// [allowAutoSave] is off. Each save ending is told to the
/// [RecordFormFeedback] of the container: a toast.
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
  }) : record = null,
       controller = null;

  /// Edits through [controller], held by whoever saves it: a button out of
  /// the form.
  const RecordForm.controlled({
    required RecordFormController<T> this.controller,
    required this.child,
    super.key,
  }) : record = null,
       api = null,
       id = null,
       fields = null,
       seed = null,
       autoSave = false,
       allowAutoSave = true,
       autoSaveDelay = Duration.zero;

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
    if (mounted && hasService<RecordFormFeedback>()) {
      getService<RecordFormFeedback>().show(context, save);
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

  /// The lines of a text.
  final int? maxLines;

  /// Offered in place of the choices of the metadata.
  final List<ComboOption<Object?>>? options;

  /// How the input draws the field, as it understands it: a style of choice.
  final Object? variant;

  /// Whether the field saves on its own; null, as the form says.
  final bool? autoSave;

  const RecordFormInput({
    required this.form,
    required this.field,
    this.label,
    this.placeholder,
    this.help,
    this.enabled = true,
    this.maxLines,
    this.options,
    this.variant,
    this.autoSave,
  });

  Object? get value => form[field.name];

  bool get required => field.required;

  /// Sets the value: [typing] while a text is being typed.
  void set(Object? value, {bool typing = false}) =>
      form.set(field.name, value, typing: typing, autoSave: autoSave);

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
class RecordFormInputs extends FieldRegistry<RecordFormInputBuilder> {}

/// The field [field] of the record of the [RecordForm] above, edited with the
/// input [RecordFormInputs] holds for it, or the one registered as [input].
/// Its label and whether it is required come from the metadata; a read-only
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
  final int? maxLines;

  /// Offered in place of the choices of the metadata.
  final List<ComboOption<Object?>>? options;

  /// How the input draws the field ([RecordFormInput.variant]).
  final Object? variant;

  /// Whether the field saves on its own; null, as the form says.
  final bool? autoSave;

  /// The metadata type of a field the metadata do not describe: a key of a
  /// JSON field.
  final String? type;

  /// The name of the input to draw it with, registered by
  /// [FieldRegistry.registerNamed], in place of the one of its type.
  final String? input;

  const RecordFormField(
    this.field, {
    super.key,
    this.label,
    this.placeholder,
    this.help,
    this.enabled = true,
    this.maxLines,
    this.options,
    this.variant,
    this.autoSave,
    this.type,
    this.input,
  });

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RecordFormScope>();

    assert(scope != null, 'A RecordFormField stands under a RecordForm');

    final fields = scope?.fields;
    final type = this.type;
    final metadata =
        fields?[field] ??
        (fields == null || type == null
            ? null
            : MetadataField(
                name: field,
                label: '',
                type: type,
                readonly: false,
                required: false,
                searchable: false,
                extra: false,
                filterOperators: const [],
              ));
    final inputs = hasService<RecordFormInputs>()
        ? getService<RecordFormInputs>()
        : null;
    final name = input;
    final builder = metadata == null
        ? null
        : name != null
        ? inputs?.named(name)
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
        maxLines: maxLines,
        options: options,
        variant: variant,
        autoSave: autoSave,
      ),
    );
  }
}
