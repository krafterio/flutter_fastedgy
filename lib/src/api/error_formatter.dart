/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

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

  /// [message] named by its field, its label or its path otherwise: « Field
  /// Email: not an email ».
  String get described {
    final label = this.label;

    return t('Field {name}: {message}', {
      'name': label == null || label.isEmpty ? field : label,
      'message': message,
    });
  }
}

/// Format API errors (especially HTTPValidationError from FastAPI/OpenAPI)
///
/// Handles two cases:
/// 1. Simple error: detail is a string
/// 2. Validation error: detail is a list of validation errors (HTTPValidationError)
///
/// For validation errors, extracts field paths from 'loc' array:
/// - loc[0] is always "body" (ignored)
/// - loc[1+] represents the field path (e.g., ["body", "workspace", "name"] -> "workspace.name")
///
/// A validation error whose location is not in the body, or is the body
/// itself, is said about no field ([FormattedError.messages]). A field is
/// named by its label in [fields], the metadata of the model written.
///
/// Example:
/// ```dart
/// try {
///   await api.create(...);
/// } catch (e) {
///   if (e is HttpError) {
///     final formatted = formatApiError(
///       e.data,
///       fields: (await api.metadata())?.fields,
///     );
///     showAlert(formatted.fullMessage);
///   }
/// }
/// ```
FormattedError formatApiError(
  dynamic errorData, {
  String? defaultTitle,
  Map<String, MetadataField>? fields,
}) {
  defaultTitle ??= t('An error occurred');

  if (errorData == null) {
    return FormattedError(title: defaultTitle);
  }

  // If errorData is not a Map, return default
  if (errorData is! Map<String, dynamic>) {
    final errorStr = errorData.toString();
    return FormattedError(title: errorStr.isNotEmpty ? errorStr : defaultTitle);
  }

  final detail = errorData['detail'];

  // Case 1: detail is a simple string
  if (detail is String && detail.isNotEmpty) {
    return FormattedError(title: detail);
  }

  // Case 2: detail is a list of validation errors (HTTPValidationError)
  if (detail is List && detail.isNotEmpty) {
    final fieldErrors = <FieldError>[];
    final messages = <String>[];

    for (final item in detail) {
      if (item is! Map<String, dynamic>) continue;

      final loc = item['loc'] as List?;
      final msg = item['msg'] as String?;
      final type = item['type'] as String?;

      if (loc == null || msg == null) continue;

      final fieldPath = loc.firstOrNull == 'body' ? _buildFieldPath(loc) : '';

      if (fieldPath.isEmpty) {
        messages.add(msg);
      } else {
        fieldErrors.add(
          FieldError.about(fieldPath, msg, fields, type: type ?? 'unknown'),
        );
      }
    }

    if (fieldErrors.isEmpty && messages.isEmpty) {
      return FormattedError(title: defaultTitle);
    }

    return FormattedError(
      title: t('Validation error'),
      fieldErrors: fieldErrors,
      messages: messages,
    );
  }

  // Try to get message from other common fields
  if (errorData['message'] is String &&
      (errorData['message'] as String).isNotEmpty) {
    return FormattedError(title: errorData['message'] as String);
  }

  if (errorData['error'] is String &&
      (errorData['error'] as String).isNotEmpty) {
    return FormattedError(title: errorData['error'] as String);
  }

  // Fallback: return the error as-is or default message
  final errorStr = errorData.toString();
  if (errorStr.isNotEmpty && errorStr != '{}' && errorStr != 'null') {
    return FormattedError(title: errorStr);
  }

  return FormattedError(title: defaultTitle);
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
