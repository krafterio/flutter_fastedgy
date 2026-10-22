/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../container/container.dart';
import '../metadata/models.dart';
import '../query/registry.dart';
import '../ui/combo_option.dart';
import 'api_record.dart';
import 'base_model.dart';
import 'record_form_controller.dart';

/// The record a form edits, for the [RecordFormField]s below it: each reads
/// its field there and writes it back. Saved by [RecordFormController.save],
/// or on its own with [autoSave].
class RecordForm<T extends BaseModel<T>> extends StatefulWidget {
  final ApiRecord<T>? record;
  final RecordFormController<T>? controller;
  final bool autoSave;
  final Duration autoSaveDelay;
  final Widget child;

  /// Edits [record] with a controller of its own, given up with the form:
  /// what waits to be saved on its own is saved then.
  const RecordForm({
    required ApiRecord<T> this.record,
    required this.child,
    super.key,
    this.autoSave = false,
    this.autoSaveDelay = const Duration(milliseconds: 600),
  }) : controller = null;

  /// Edits through [controller], held by whoever saves it: a button out of
  /// the form.
  const RecordForm.controlled({
    required RecordFormController<T> this.controller,
    required this.child,
    super.key,
  }) : record = null,
       autoSave = false,
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
  late final RecordFormController<T> _own = RecordFormController<T>(
    widget.record!,
    autoSave: widget.autoSave,
    autoSaveDelay: widget.autoSaveDelay,
  );

  RecordFormController<T> get _controller => widget.controller ?? _own;

  Map<String, MetadataField>? _fields;

  @override
  void initState() {
    super.initState();
    unawaited(_readFields());
  }

  Future<void> _readFields() async {
    final fields = (await _controller.record.api.metadata())?.fields;

    if (mounted) {
      setState(() => _fields = fields ?? const {});
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _own.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RecordFormScope(
    controller: _controller,
    fields: _fields,
    child: widget.child,
  );
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
  });

  Object? get value => form[field.name];

  bool get required => field.required;

  /// Sets the value: [typing] while a text is being typed.
  void set(Object? value, {bool typing = false}) =>
      form.set(field.name, value, typing: typing);

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
/// input [RecordFormInputs] holds for it. Its label and whether it is required
/// come from the metadata; a read-only field cannot be changed. Nothing shows
/// while the metadata is read, nor for a field no input is registered for.
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
  });

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RecordFormScope>();

    assert(scope != null, 'A RecordFormField stands under a RecordForm');

    final metadata = scope?.fields?[field];
    final input = metadata == null || !hasService<RecordFormInputs>()
        ? null
        : getService<RecordFormInputs>().of(metadata);

    if (scope == null || metadata == null || input == null) {
      return const SizedBox.shrink();
    }

    final label = this.label ?? metadata.label;

    return input(
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
      ),
    );
  }
}
