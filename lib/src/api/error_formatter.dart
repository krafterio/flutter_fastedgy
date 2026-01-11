/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// Formatted error message with title and optional field errors
class FormattedError {
  final String title;
  final List<FieldError> fieldErrors;

  const FormattedError({
    required this.title,
    this.fieldErrors = const [],
  });

  /// Check if there are field-specific errors
  bool get hasFieldErrors => fieldErrors.isNotEmpty;

  /// Get a single formatted message (title + field errors)
  String get fullMessage {
    if (fieldErrors.isEmpty) {
      return title;
    }

    final buffer = StringBuffer(title);
    buffer.writeln();
    buffer.writeln();

    for (final error in fieldErrors) {
      buffer.writeln('• ${error.field}: ${error.message}');
    }

    return buffer.toString().trim();
  }
}

/// Represents a field-specific error
class FieldError {
  final String field;
  final String message;
  final String type;

  const FieldError({
    required this.field,
    required this.message,
    required this.type,
  });
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
/// Example:
/// ```dart
/// try {
///   await api.create(...);
/// } catch (e) {
///   if (e is HttpError) {
///     final formatted = formatApiError(e.response?.data);
///     showAlert(formatted.fullMessage);
///   }
/// }
/// ```
FormattedError formatApiError(dynamic errorData, {String? defaultTitle}) {
  defaultTitle ??= t('An error occurred');

  if (errorData == null) {
    return FormattedError(title: defaultTitle);
  }

  // If errorData is not a Map, return default
  if (errorData is! Map<String, dynamic>) {
    final errorStr = errorData.toString();
    return FormattedError(
      title: errorStr.isNotEmpty ? errorStr : defaultTitle,
    );
  }

  final detail = errorData['detail'];

  // Case 1: detail is a simple string
  if (detail is String && detail.isNotEmpty) {
    return FormattedError(title: detail);
  }

  // Case 2: detail is a list of validation errors (HTTPValidationError)
  if (detail is List && detail.isNotEmpty) {
    final fieldErrors = <FieldError>[];

    for (final item in detail) {
      if (item is! Map<String, dynamic>) continue;

      final loc = item['loc'] as List?;
      final msg = item['msg'] as String?;
      final type = item['type'] as String?;

      if (loc == null || msg == null) continue;

      // Build field path from loc (skip first element which is always "body")
      final fieldPath = _buildFieldPath(loc);

      fieldErrors.add(FieldError(
        field: fieldPath.isEmpty ? 'unknown' : fieldPath,
        message: msg,
        type: type ?? 'unknown',
      ));
    }

    if (fieldErrors.isEmpty) {
      return FormattedError(title: defaultTitle);
    }

    // Group errors by field if needed, or return all
    return FormattedError(
      title: 'Erreur de validation',
      fieldErrors: fieldErrors,
    );
  }

  // Try to get message from other common fields
  if (errorData['message'] is String && (errorData['message'] as String).isNotEmpty) {
    return FormattedError(title: errorData['message'] as String);
  }

  if (errorData['error'] is String && (errorData['error'] as String).isNotEmpty) {
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
