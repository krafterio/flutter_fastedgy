/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../fetcher/http_error.dart';
import '../i18n/i18n.dart';
import '../metadata/models.dart';

/// An error worded for the screen: its [title], what it says about a field
/// ([fieldErrors]) and about none ([messages]).
class FormattedError {
  final String title;
  final List<FieldError> fieldErrors;

  /// What the error says about no field.
  final List<String> messages;

  const FormattedError({
    required this.title,
    this.fieldErrors = const [],
    this.messages = const [],
  });

  /// Check if there are field-specific errors
  bool get hasFieldErrors => fieldErrors.isNotEmpty;

  /// Each thing the error says: its [messages], then its [fieldErrors], each
  /// named by its field ([FieldError.described]).
  List<String> get points => [
    ...messages,
    for (final error in fieldErrors) error.described,
  ];

  /// The error in one message, for a toast or a dialog: a point alone, or the
  /// [title] over its points, one bullet each; the [title] when it says none.
  String get fullMessage => switch (points) {
    [] => title,
    [final point] => point,
    final points => [title, for (final point in points) '• $point'].join('\n'),
  };
}

/// Represents a field-specific error
class FieldError {
  final String field;

  /// The name the metadata give the field, null when they do not describe it.
  final String? label;

  final String message;
  final String type;

  const FieldError({
    required this.field,
    required this.message,
    required this.type,
    this.label,
  });

  /// [message] about the field at [field], named by its label in [fields]:
  /// the label of a JSON field or of a list for a path inside them.
  FieldError.about(
    this.field,
    this.message,
    Map<String, MetadataField>? fields, {
    this.type = '',
  }) : label = fields?[field.split(RegExp(r'[.\[]')).first]?.label;

  /// [message] named by the label of its field, « Field Email: not an
  /// email »; alone for a field the metadata do not name.
  String get described {
    final label = this.label;

    return label == null || label.isEmpty
        ? message
        : t('Field {name}: {message}', {'name': label, 'message': message});
  }
}

/// [error] worded for the screen, a failed call of the fetcher
/// ([HttpError]): the reason the server gives (`detail` as a text, or the
/// `message` of a `detail` object, else the `message` or `error` of the
/// body), [defaultMessage] when it gives none (the network down, an answer
/// without a body), « An error occurred » without one.
///
/// A validation error (`detail` as a list, FastAPI's HTTPValidationError) is
/// titled « Validation error »: what it says about a field of the body goes to
/// [FormattedError.fieldErrors], its path read from `loc` (`["body", "items",
/// 0, "value"]` to `items[0].value`) and named by its label in [fields], the
/// metadata of the model written; the rest to [FormattedError.messages], a
/// position in the body included (`["body", 12]`, a JSON that does not
/// parse). The prefix pydantic gives the message of a validator (« Value
/// error, », « Assertion failed, ») is left out.
///
/// The same as `formatApiError` of vue-fastedgy.
///
/// ```dart
/// try {
///   await api.create(...);
/// } catch (error) {
///   final formatted = formatApiError(
///     error,
///     fields: (await api.metadata())?.fields,
///   );
///   showAlert(formatted.fullMessage);
/// }
/// ```
FormattedError formatApiError(
  Object? error, {
  String? defaultMessage,
  Map<String, MetadataField>? fields,
}) {
  final fallback = FormattedError(
    title: defaultMessage ?? t('An error occurred'),
  );
  final data = error is HttpError ? error.data : null;

  if (data is! Map) {
    return fallback;
  }

  final detail = data['detail'];

  if (detail is String && detail.isNotEmpty) {
    return FormattedError(title: detail);
  }

  if (detail is Map) {
    final said = detail['message'];

    if (said is String && said.isNotEmpty) {
      return FormattedError(title: said);
    }
  }

  if (detail is List) {
    final fieldErrors = <FieldError>[];
    final messages = <String>[];

    for (final item in detail) {
      final msg = item is Map ? _reason(item) : null;

      if (msg == null) continue;

      final loc = item['loc'];
      final path =
          loc is List &&
              loc.firstOrNull == 'body' &&
              loc.elementAtOrNull(1) is String
          ? _buildFieldPath(loc)
          : '';

      if (path.isEmpty) {
        messages.add(msg);
      } else {
        fieldErrors.add(
          FieldError.about(
            path,
            msg,
            fields,
            type: item['type'] as String? ?? 'unknown',
          ),
        );
      }
    }

    return fieldErrors.isEmpty && messages.isEmpty
        ? fallback
        : FormattedError(
            title: t('Validation error'),
            fieldErrors: fieldErrors,
            messages: messages,
          );
  }

  for (final key in const ['message', 'error']) {
    final said = data[key];

    if (said is String && said.isNotEmpty) {
      return FormattedError(title: said);
    }
  }

  return fallback;
}

/// [error] in one message ([FormattedError.fullMessage] of
/// [formatApiError]); null without one. The same as `formatValidationErrors`
/// of vue-fastedgy.
String? formatValidationErrors(
  Object? error, {
  String? defaultMessage,
  Map<String, MetadataField>? fields,
}) => error == null
    ? null
    : formatApiError(
        error,
        defaultMessage: defaultMessage,
        fields: fields,
      ).fullMessage;

/// What a validation error [item] says, the prefix pydantic gives the message
/// of a validator left out; null when it says nothing.
String? _reason(Map<dynamic, dynamic> item) {
  final msg = item['msg'];

  if (msg is! String || msg.isEmpty) {
    return null;
  }

  final prefix = switch (item['type']) {
    'value_error' => 'Value error, ',
    'assertion_error' => 'Assertion failed, ',
    _ => null,
  };

  return prefix != null && msg.startsWith(prefix)
      ? msg.substring(prefix.length)
      : msg;
}

/// Build field path from loc array, skipping "body"
///
/// Examples:
/// - ["body", "workspace", "name"] -> "workspace.name"
/// - ["body", "email"] -> "email"
/// - ["body", "items", 0, "value"] -> "items[0].value"
String _buildFieldPath(List<dynamic> loc) {
  final parts = <String>[];

  for (var i = 0; i < loc.length; i++) {
    final segment = loc[i];

    // Skip first element if it's "body"
    if (i == 0 && segment == 'body') {
      continue;
    }

    if (segment is int) {
      // Array index: append as [index]
      if (parts.isNotEmpty) {
        parts[parts.length - 1] += '[$segment]';
      } else {
        parts.add('[$segment]');
      }
    } else {
      parts.add(segment.toString());
    }
  }

  return parts.join('.');
}
