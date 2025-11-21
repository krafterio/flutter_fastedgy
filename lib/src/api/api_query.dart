/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Query parameters for list operations
class ListQuery {
  /// Page number (1-based)
  final int? page;

  /// Page size
  final int? size;

  /// Direct limit (alternative to page/size)
  final int? limit;

  /// Direct offset (alternative to page/size)
  final int? offset;

  /// Fields to select (string or list of strings)
  final dynamic fields;

  /// Filter expression (string or map)
  final dynamic filter;

  /// Order by expression (string or list of strings)
  final dynamic orderBy;

  const ListQuery({
    this.page,
    this.size,
    this.limit,
    this.offset,
    this.fields,
    this.filter,
    this.orderBy,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (page != null) map['page'] = page;
    if (size != null) map['size'] = size;
    if (limit != null) map['limit'] = limit;
    if (offset != null) map['offset'] = offset;
    if (fields != null) map['fields'] = fields;
    if (filter != null) map['filter'] = filter;
    if (orderBy != null) map['orderBy'] = orderBy;
    return map;
  }
}

/// Options for field selection
class FieldsOptions {
  /// Fields to select (string or list of strings)
  final dynamic fields;

  const FieldsOptions({this.fields});

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (fields != null) map['fields'] = fields;
    return map;
  }
}

/// Export query parameters
class ExportQuery {
  /// Export format (csv, xlsx, json)
  final String? format;

  /// Page number (1-based)
  final int? page;

  /// Page size
  final int? size;

  /// Direct limit
  final int? limit;

  /// Direct offset
  final int? offset;

  /// Fields to export (string or list of strings)
  final dynamic fields;

  /// Filter expression (string or map)
  final dynamic filter;

  /// Order by expression (string or list of strings)
  final dynamic orderBy;

  const ExportQuery({
    this.format,
    this.page,
    this.size,
    this.limit,
    this.offset,
    this.fields,
    this.filter,
    this.orderBy,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (format != null) map['format'] = format;
    if (page != null) map['page'] = page;
    if (size != null) map['size'] = size;
    if (limit != null) map['limit'] = limit;
    if (offset != null) map['offset'] = offset;
    if (fields != null) map['fields'] = fields;
    if (filter != null) map['filter'] = filter;
    if (orderBy != null) map['orderBy'] = orderBy;
    return map;
  }
}

/// API call parameters
class ApiParams {
  /// API prefix override (e.g., '/admin')
  final String? prefix;

  /// Additional headers
  final Map<String, dynamic>? headers;

  const ApiParams({
    this.prefix,
    this.headers,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (prefix != null) map['prefix'] = prefix;
    if (headers != null) map['headers'] = headers;
    return map;
  }
}
