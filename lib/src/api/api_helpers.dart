/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

/// Helper utilities for FastEdgy API encoding
///
/// These functions handle the encoding of special headers and query parameters
/// used by the FastEdgy backend API.
class ApiHelpers {
  ApiHelpers._();

  /// Encode a filter expression for the X-Filter header
  ///
  /// If [filter] is already a String, it's returned as-is.
  /// Otherwise, it's JSON-encoded.
  ///
  /// Example:
  /// ```dart
  /// // Simple filter
  /// ApiHelpers.encodeFilter(['name', 'eq', 'John']); // '["name","eq","John"]'
  ///
  /// // Complex filter
  /// ApiHelpers.encodeFilter(['&', [['active', 'eq', true], ['role', 'eq', 'admin']]]);
  /// ```
  static String encodeFilter(dynamic filter) {
    if (filter == null) return '';
    if (filter is String) return filter;
    return jsonEncode(filter);
  }

  /// Encode a filter expression for URL (URI encoded)
  ///
  /// Same as [encodeFilter] but also URI-encodes the result.
  static String encodeFilterForUrl(dynamic filter) {
    if (filter == null) return '';
    if (filter is String) return Uri.encodeComponent(filter);
    return Uri.encodeComponent(jsonEncode(filter));
  }

  /// Encode fields for the X-Fields header
  ///
  /// If [fields] is a List, joins with commas.
  /// Otherwise, returns as string.
  ///
  /// Example:
  /// ```dart
  /// ApiHelpers.encodeFields(['id', 'name', 'email']); // 'id,name,email'
  /// ApiHelpers.encodeFields('+,user.name'); // '+,user.name'
  /// ```
  static String encodeFields(dynamic fields) {
    if (fields == null) return '';
    if (fields is List) return fields.join(',');
    return fields.toString();
  }

  /// Encode orderBy for the order_by query parameter
  ///
  /// Supports various formats:
  /// - String: returned as-is
  /// - List of strings: joined with commas
  /// - List of tuples: formatted as 'field:direction'
  /// - Record/Map: formatted as 'field:direction'
  ///
  /// Example:
  /// ```dart
  /// ApiHelpers.encodeOrderBy('name'); // 'name'
  /// ApiHelpers.encodeOrderBy(['name', 'created_at']); // 'name,created_at'
  /// ApiHelpers.encodeOrderBy([['name', 'asc'], ['id', 'desc']]); // 'name:asc,id:desc'
  /// ```
  static String encodeOrderBy(dynamic orderBy) {
    if (orderBy == null) return '';
    if (orderBy is String) return orderBy;
    if (orderBy is List) {
      // Check if it's a single tuple ['field', 'direction']
      if (orderBy.length == 2 && orderBy[0] is String && orderBy[1] is String) {
        final second = orderBy[1] as String;
        if (second == 'asc' || second == 'desc') {
          return '${orderBy[0]}:${orderBy[1]}';
        }
      }
      // List of items
      return orderBy.map((item) => _formatOrderByItem(item)).join(',');
    }
    if (orderBy is Map && orderBy.length == 1) {
      final entry = orderBy.entries.first;
      return '${entry.key}:${entry.value}';
    }
    // Handle Dart Record (tuple) like ('field', 'direction')
    if (orderBy is (String, String)) {
      return '${orderBy.$1}:${orderBy.$2}';
    }
    return orderBy.toString();
  }

  static String _formatOrderByItem(dynamic item) {
    if (item is String) return item;
    if (item is List && item.length == 2) {
      return '${item[0]}:${item[1]}';
    }
    if (item is Map && item.length == 1) {
      final entry = item.entries.first;
      return '${entry.key}:${entry.value}';
    }
    // Handle Dart Record (tuple) like ('field', 'direction')
    if (item is (String, String)) {
      return '${item.$1}:${item.$2}';
    }
    return item.toString();
  }

  /// Process headers map, encoding special headers (X-Filter, X-Fields)
  ///
  /// This is useful when building headers from a Map that may contain
  /// non-string values for X-Filter or X-Fields.
  static Map<String, dynamic> processHeaders(Map<String, dynamic>? headers) {
    if (headers == null) return {};
    final result = <String, dynamic>{};
    for (final entry in headers.entries) {
      switch (entry.key) {
        case 'X-Filter':
          result[entry.key] = entry.value is String ? entry.value : encodeFilter(entry.value);
          break;
        case 'X-Fields':
          result[entry.key] = entry.value is List ? (entry.value as List).join(',') : entry.value.toString();
          break;
        default:
          result[entry.key] = entry.value?.toString() ?? '';
      }
    }
    return result;
  }

  /// Process query parameters, encoding special params (order_by)
  static Map<String, dynamic> processQueryParams(Map<String, dynamic>? params) {
    if (params == null) return {};
    final result = <String, dynamic>{};
    for (final entry in params.entries) {
      if (entry.key == 'order_by' && entry.value is! String) {
        result[entry.key] = encodeOrderBy(entry.value);
      } else {
        result[entry.key] = entry.value?.toString() ?? '';
      }
    }
    return result;
  }

  /// Build query parameters from a standardized query object
  ///
  /// Handles:
  /// - Pagination: page/size → limit/offset, or direct limit/offset
  /// - Ordering: orderBy → order_by
  /// - Format: format (for exports)
  static Map<String, dynamic> buildQueryParams(Map<String, dynamic> query) {
    final result = <String, dynamic>{};

    // Pagination: page + size → limit + offset
    if (query['page'] != null && query['size'] != null) {
      final page = query['page'] as int;
      final size = query['size'] as int;
      result['limit'] = size;
      result['offset'] = (page - 1) * size;
    } else if (query['size'] != null) {
      result['limit'] = query['size'];
    }

    // Direct limit/offset
    if (query['limit'] != null) result['limit'] = query['limit'];
    if (query['offset'] != null) result['offset'] = query['offset'];

    // Ordering
    if (query['orderBy'] != null) {
      result['order_by'] = encodeOrderBy(query['orderBy']);
    }

    // Export format
    if (query['format'] != null) result['format'] = query['format'];

    return result;
  }

  /// Build headers from a standardized query object
  ///
  /// Handles:
  /// - X-Fields: fields selection
  /// - X-Filter: filtering expression
  static Map<String, dynamic> buildHeaders(
    Map<String, dynamic> query, {
    Map<String, dynamic>? extraHeaders,
  }) {
    final result = <String, dynamic>{
      ...?extraHeaders,
    };

    if (query['fields'] != null) {
      result['X-Fields'] = encodeFields(query['fields']);
    }

    if (query['filter'] != null) {
      result['X-Filter'] = encodeFilter(query['filter']);
    }

    return result;
  }
}
