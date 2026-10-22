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
import '../ui/theme/theme.dart';
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
  /// application, whose routes are its own, as any other. Without [id], a
  /// record to create, created by its first save.
  const RecordForm.api({
    required ApiModel<T> this.api,
    required this.child,
    super.key,
    this.id,
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

    if (api != null) {
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

  RecordFormFeedback get _feedback =>
      widget.feedback ??
      (hasService<RecordFormFeedback>()
          ? getService<RecordFormFeedback>()
          : const RecordFormFeedback());

  void _tell(RecordFormSave save) {
    final record = _controller.record.value;

    if (!mounted) {
      return;
    }

    _feedback.show(context, save);

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
    feedback: _feedback,
    child: widget.child,
  );
}

/// How a [RecordForm] says its saves: a service of the container registered
/// by [initializeFastEdgy]. An application registers its own before it
/// starts: a toast once saved, its own look for a message under a field
/// ([field]) or for the alert of a form ([alert]), or a toast in place of the
/// alert ([alertInForm] off, [show] saying [RecordFormSave.alerts]).
class RecordFormFeedback {
  const RecordFormFeedback();

  /// Told of each save as it ends, written or refused: silent here.
  void show(BuildContext context, RecordFormSave save) {}

  /// [input] with [error] under it, when it has one.
  Widget field(BuildContext context, Widget input, String? error) {
    if (error == null) {
      return input;
    }

    final theme = FastEdgyTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        input,
        Padding(
          padding: EdgeInsets.only(top: theme.spacing * 1.5),
          child: Text(
            error,
            style: theme.typography.small.copyWith(color: theme.colors.danger),
          ),
        ),
      ],
    );
  }

  /// Whether the alert of a form says the messages about no field shown
  /// ([RecordFormAlert]); off, they are left to [show].
  bool get alertInForm => true;

  /// The alert of a form showing [messages] ([RecordFormAlert]).
  Widget alert(BuildContext context, List<String> messages) {
    final theme = FastEdgyTheme.of(context);
    final danger = theme.colors.danger;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.all(theme.spacing * 3),
        decoration: BoxDecoration(
          color: danger.withValues(alpha: 0.08),
          border: Border.all(color: danger.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(theme.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: theme.spacing,
          children: [
            for (final message in messages)
              Text(
                message,
                style: theme.typography.body.copyWith(color: danger),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordFormScope
    extends InheritedNotifier<RecordFormController<dynamic>> {
  final Map<String, MetadataField>? fields;
  final RecordFormFeedback feedback;

  const _RecordFormScope({
    required RecordFormController<dynamic> controller,
    required this.fields,
    required this.feedback,
    required super.child,
  }) : super(notifier: controller);

  RecordFormController<dynamic> get controller => notifier!;

  @override
  bool updateShouldNotify(_RecordFormScope oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      fields != oldWidget.fields ||
      feedback != oldWidget.feedback;
}

/// Why the last save of the [RecordForm] above was refused, about no field it
/// shows: the alert of its [RecordFormFeedback], where the screen lays it.
/// Nothing while there is nothing to say, nor when the feedback gives no
/// alert (it says them otherwise).
class RecordFormAlert extends StatefulWidget {
  const RecordFormAlert({super.key, this.padding = EdgeInsets.zero});

  /// The room around the alert where the screen lays it, given only while it
  /// shows.
  final EdgeInsetsGeometry padding;

  @override
  State<RecordFormAlert> createState() => _RecordFormAlertState();
}

class _RecordFormAlertState extends State<RecordFormAlert> {
  /// The form told this alert shows its messages.
  RecordFormController<dynamic>? _shows;

  void _follow(RecordFormController<dynamic>? form) {
    if (!identical(form, _shows)) {
      _shows?.detachAlert();
      _shows = form;
      form?.attachAlert();
    }
  }

  @override
  void dispose() {
    _shows?.detachAlert();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RecordFormScope>();
    final inForm = scope != null && scope.feedback.alertInForm;

    _follow(inForm ? scope.controller : null);

    final alerts = inForm ? scope.controller.alerts : const <String>[];

    return alerts.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: widget.padding,
            child: scope!.feedback.alert(context, alerts),
          );
  }
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

  /// Told of each value taken, once the form holds it.
  final ValueChanged<Object?>? onChanged;

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
    this.onChanged,
  });

  /// What the form holds of the field, its default while it holds none.
  Object? get value => form[field.name] ?? field.defaultValue;

  bool get required => field.required;

  /// Sets the value, unless [guard] refuses it: [typing] while a text is
  /// being typed.
  void set(Object? value, {bool typing = false}) {
    if (guard?.call(value) ?? true) {
      form.set(field.name, value, typing: typing, autoSave: autoSave);
      onChanged?.call(value);
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
///
/// Why a save was refused about it, by [validator] or by the server, shows
/// under it as the [RecordFormFeedback] of the form says ([RecordFormFeedback.field]).
class RecordFormField extends StatefulWidget {
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

  /// Whether the field is to be filled, in place of what the metadata say.
  final bool? required;

  /// Whether a value set is taken: false leaves the field as it is (an offer
  /// shown in place of turning a paid option on).
  final bool Function(Object? value)? guard;

  /// Told of each value taken, once the form holds it: a field that sets
  /// another along with it.
  final ValueChanged<Object?>? onChanged;

  /// What its value has to fix before a save asked for, said under it.
  final RecordFormFieldValidator? validator;

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
    this.required,
    this.guard,
    this.onChanged,
    this.validator,
  });

  @override
  State<RecordFormField> createState() => _RecordFormFieldState();
}

class _RecordFormFieldState extends State<RecordFormField> {
  /// The input, kept as it is (its focus, its text) while the feedback lays
  /// a message under it or takes it away.
  final _input = GlobalKey();

  /// The form told this field shows, and under which path.
  RecordFormController<dynamic>? _form;
  String? _shown;

  void _follow(RecordFormController<dynamic>? form) {
    if (!identical(form, _form) || _shown != widget.field) {
      if (_shown case final field?) {
        _form?.detach(field);
      }

      _form = form;
      _shown = form == null ? null : widget.field;
      form?.attach(widget.field, validator: widget.validator);
    } else if (widget.validator case final validator?) {
      form?.check(widget.field, validator);
    }
  }

  @override
  void dispose() {
    if (_shown case final field?) {
      _form?.detach(field);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RecordFormField(
      :field,
      :label,
      :placeholder,
      :help,
      :enabled,
      :options,
      :input,
      :autoSave,
      :type,
      :defaultValue,
      :required,
      :guard,
      :onChanged,
    ) = widget;
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RecordFormScope>();

    assert(scope != null, 'A RecordFormField stands under a RecordForm');

    _follow(scope?.controller);

    final described = scope?.fields?[field];
    final metadata = scope?.fields == null
        ? null
        : described == null && type == null && input == null
        ? null
        : MetadataField(
            name: field,
            label: described?.label ?? '',
            type: described?.type ?? type ?? '',
            readonly: described?.readonly ?? false,
            required: required ?? described?.required ?? false,
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

    final shown = label ?? metadata.label;

    return scope.feedback.field(
      context,
      KeyedSubtree(
        key: _input,
        child: builder(
          context,
          RecordFormInput(
            form: scope.controller,
            field: metadata,
            label: shown.isEmpty ? null : shown,
            placeholder: placeholder,
            help: help,
            enabled:
                enabled && !metadata.readonly && metadata.type != 'computed',
            options: options,
            input: input,
            autoSave: autoSave,
            guard: guard,
            onChanged: onChanged,
          ),
        ),
      ),
      scope.controller.errorOf(field),
    );
  }
}
