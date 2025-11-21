/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../i18n/i18n.dart';

/// Validation error detail from FastAPI
class ValidationError {
  /// Location of the error (e.g., ['body', 'email'])
  final List<dynamic> loc;

  /// Error message
  final String msg;

  /// Error type (e.g., 'value_error.email')
  final String type;

  ValidationError({
    required this.loc,
    required this.msg,
    required this.type,
  });

  factory ValidationError.fromJson(Map<String, dynamic> json) {
    return ValidationError(
      loc: json['loc'] as List<dynamic>,
      msg: json['msg'] as String,
      type: json['type'] as String,
    );
  }

  /// Get formatted field name from location
  String get field => loc.skip(1).join('.');

  @override
  String toString() => '$field: $msg';
}

/// HTTP error with response details
///
/// Thrown when an HTTP request fails with a non-2xx status code
class HttpError implements Exception {
  /// The original Dio response
  final Response? response;

  /// HTTP status code
  final int? statusCode;

  /// Error message
  final String message;

  /// Parsed response data (JSON or raw)
  final dynamic data;

  /// Validation errors (for 422 status code)
  final List<ValidationError>? validationErrors;

  HttpError({
    required this.message,
    this.response,
    this.statusCode,
    this.data,
    this.validationErrors,
  });

  /// Create an HttpError from a DioException
  factory HttpError.fromDioException(DioException e) {
    final response = e.response;
    final statusCode = response?.statusCode;
    final data = response?.data;

    List<ValidationError>? validationErrors;
    String message;

    if (statusCode != null) {
      message = t('HTTP {status}', {'status': statusCode.toString()});

      // Handle FastAPI validation errors (422)
      if (statusCode == 422 && data is Map && data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is List) {
          validationErrors = detail
              .map((e) => ValidationError.fromJson(e as Map<String, dynamic>))
              .toList();

          // Create a readable message from validation errors
          if (validationErrors.isNotEmpty) {
            final firstError = validationErrors.first;
            message = t('{field}: {message}', {
              'field': firstError.field,
              'message': firstError.msg,
            });
          }
        } else if (detail is String) {
          message = detail;
        }
      } else if (data is Map && data.containsKey('detail')) {
        // Generic detail message
        final detail = data['detail'];
        message = detail is String ? detail : t('HTTP {status}', {'status': statusCode.toString()});
      } else if (data is Map && data.containsKey('message')) {
        message = data['message'] as String;
      }
    } else {
      message = e.message ?? t('Network error');
    }

    return HttpError(
      message: message,
      response: response,
      statusCode: statusCode,
      data: data,
      validationErrors: validationErrors,
    );
  }

  @override
  String toString() => message;
}
