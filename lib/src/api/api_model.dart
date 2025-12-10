/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'package:dio/dio.dart';
import '../fetcher/client.dart';
import '../container/container.dart';
import 'pagination_result.dart';
import 'api_query.dart';

/// Base class for API Models
///
/// Provides CRUD operations for a REST API resource.
/// Similar to vue-fastedgy's useApiModel.
///
/// Example:
/// ```dart
/// class User {
///   final String id;
///   final String name;
///   final String email;
///
///   User({required this.id, required this.name, required this.email});
///
///   factory User.fromJson(Map<String, dynamic> json) {
///     return User(
///       id: json['id'] as String,
///       name: json['name'] as String,
///       email: json['email'] as String,
///     );
///   }
///
///   Map<String, dynamic> toJson() {
///     return {'id': id, 'name': name, 'email': email};
///   }
/// }
///
/// class UserApi extends ApiModel<User> {
///   UserApi() : super('/users');
///
///   @override
///   User fromJson(Map<String, dynamic> json) => User.fromJson(json);
/// }
///
/// // Usage
/// final userApi = UserApi();
/// final users = await userApi.list(params: {'page': 1, 'limit': 25});
/// final user = await userApi.get(123); // or '123'
/// final created = await userApi.create({'name': 'John', 'email': 'john@example.com'});
/// ```
abstract class ApiModel<T> {
  /// The base path for this resource (e.g., '/users')
  final String basePath;

  /// The HTTP client used for requests
  final Fetcher _fetcher;

  /// Create an API model for a specific resource
  ///
  /// [basePath] is the base URL path for this resource (e.g., '/users')
  /// [fetcher] is optional; if not provided, uses the global Fetcher from DI
  ApiModel(this.basePath, {Fetcher? fetcher})
      : _fetcher = fetcher ?? getService<Fetcher>();

  /// Convert JSON to model instance
  ///
  /// Must be implemented by subclasses.
  T fromJson(Map<String, dynamic> json);

  /// List resources with pagination
  ///
  /// [query] includes pagination, fields, filter, orderBy
  /// [params] includes prefix and headers overrides
  ///
  /// Returns a [PaginationResult] with items and metadata.
  ///
  /// Example:
  /// ```dart
  /// final result = await api.list(
  ///   query: ListQuery(
  ///     page: 1,
  ///     size: 25,
  ///     fields: ['id', 'name'],
  ///     filter: {'status': 'active'},
  ///     orderBy: ['name:asc'],
  ///   ),
  /// );
  /// ```
  Future<PaginationResult<T>> list({
    ListQuery? query,
    ApiParams? params,
  }) async {
    final queryMap = query?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final queryParams = _buildQueryParams(queryMap);
    final headers = _buildHeaders(queryMap, paramsMap);

    final response = await _fetcher.get(
      basePath,
      params: queryParams,
      headers: headers,
    );

    return PaginationResult.fromJson(
      response.data as Map<String, dynamic>,
      fromJson,
    );
  }

  /// Get a single resource by ID
  ///
  /// [id] is the resource identifier (String or int)
  /// [options] includes field selection
  /// [params] includes prefix and headers overrides
  ///
  /// Example:
  /// ```dart
  /// final item = await api.get(
  ///   123, // or '123'
  ///   options: FieldsOptions(fields: ['id', 'name']),
  /// );
  /// ```
  Future<T> get(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = _buildHeaders(optionsMap, paramsMap);

    final response = await _fetcher.get(
      '$basePath/${id.toString()}',
      headers: headers,
    );

    return fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new resource
  ///
  /// [payload] is the resource data to create
  /// [options] includes field selection for response
  /// [params] includes prefix and headers overrides
  ///
  /// Returns the created resource
  ///
  /// Example:
  /// ```dart
  /// final created = await api.create(
  ///   {'name': 'John', 'email': 'john@example.com'},
  ///   options: FieldsOptions(fields: ['id', 'name']),
  /// );
  /// ```
  Future<T> create(
    Map<String, dynamic> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = _buildHeaders(optionsMap, paramsMap);

    final response = await _fetcher.post(
      basePath,
      payload,
      headers: headers,
    );

    return fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an existing resource (PATCH)
  ///
  /// [id] is the resource identifier (String or int)
  /// [payload] is the updated resource data
  /// [options] includes field selection for response
  /// [params] includes prefix and headers overrides
  ///
  /// Returns the updated resource
  ///
  /// Example:
  /// ```dart
  /// final updated = await api.update(
  ///   123, // or '123'
  ///   {'name': 'Jane'},
  ///   options: FieldsOptions(fields: ['id', 'name']),
  /// );
  /// ```
  Future<T> update(
    Object id,
    Map<String, dynamic> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = _buildHeaders(optionsMap, paramsMap);

    final response = await _fetcher.patch(
      '$basePath/${id.toString()}',
      payload,
      headers: headers,
    );

    return fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a resource
  ///
  /// [id] is the resource identifier (String or int)
  /// [params] includes prefix and headers overrides
  ///
  /// Example:
  /// ```dart
  /// await api.delete(123); // or '123'
  /// ```
  Future<void> delete(
    Object id, {
    ApiParams? params,
  }) async {
    final paramsMap = params?.toMap() ?? {};
    final headers = paramsMap['headers'] as Map<String, dynamic>?;

    await _fetcher.delete(
      '$basePath/${id.toString()}',
      headers: headers,
    );
  }

  /// Export resources
  ///
  /// [query] includes format, pagination, fields, filter, orderBy
  /// [params] includes prefix and headers overrides
  ///
  /// Returns the raw response data (typically bytes for files)
  ///
  /// Example:
  /// ```dart
  /// final response = await api.export(
  ///   query: ExportQuery(
  ///     format: 'csv',
  ///     fields: ['id', 'name'],
  ///     filter: {'status': 'active'},
  ///   ),
  /// );
  /// ```
  Future<Response> export({
    ExportQuery? query,
    ApiParams? params,
  }) async {
    final queryMap = query?.toMap() ?? {};
    if (queryMap['format'] == null) {
      queryMap['format'] = 'csv';
    }

    final paramsMap = params?.toMap() ?? {};
    final queryParams = _buildQueryParams(queryMap);
    final headers = _buildHeaders(queryMap, paramsMap);

    return _fetcher.get(
      '$basePath/export',
      params: queryParams,
      headers: headers,
      responseType: ResponseType.bytes,
    );
  }

  /// Import resources from file
  ///
  /// [file] is the file bytes to import (CSV, XLSX, ODS)
  /// [fileName] is the original file name
  /// [params] includes prefix and headers overrides
  ///
  /// Returns import result with success/error counts
  ///
  /// Example:
  /// ```dart
  /// final response = await api.import(
  ///   fileBytes,
  ///   'data.csv',
  /// );
  /// ```
  Future<Response> import(
    List<int> file,
    String fileName, {
    ApiParams? params,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        file,
        filename: fileName,
      ),
    });

    final paramsMap = params?.toMap() ?? {};
    final headers = paramsMap['headers'] as Map<String, dynamic>?;

    return _fetcher.post(
      '$basePath/import',
      formData,
      headers: headers,
    );
  }

  /// Custom GET request on this resource
  ///
  /// Useful for custom endpoints like `/users/me` or `/users/search`
  Future<Response> customGet(
    String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
  }) async {
    return _fetcher.get(
      '$basePath$path',
      params: params,
      headers: headers,
      id: id,
    );
  }

  /// Custom POST request on this resource
  ///
  /// Useful for custom actions like `/users/bulk-create`
  Future<Response> customPost(
    String path,
    dynamic data, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
  }) async {
    return _fetcher.post(
      '$basePath$path',
      data,
      params: params,
      headers: headers,
      id: id,
    );
  }

  /// Build query parameters from standardized query object
  Map<String, dynamic> _buildQueryParams(Map<String, dynamic> query) {
    final queryParams = <String, dynamic>{};

    // Standard pagination (page + size → limit + offset)
    if (query['page'] != null && query['size'] != null) {
      final page = query['page'] as int;
      final size = query['size'] as int;
      queryParams['limit'] = size;
      queryParams['offset'] = (page - 1) * size;
    } else {
      if (query['size'] != null) queryParams['limit'] = query['size'];
    }

    // Direct limit/offset
    if (query['limit'] != null) queryParams['limit'] = query['limit'];
    if (query['offset'] != null) queryParams['offset'] = query['offset'];

    // Standard ordering (orderBy → order_by)
    if (query['orderBy'] != null) {
      final orderBy = query['orderBy'];
      queryParams['order_by'] = orderBy is List
          ? orderBy.join(',')
          : orderBy.toString();
    }

    // Export format
    if (query['format'] != null) queryParams['format'] = query['format'];

    return queryParams;
  }

  /// Build headers from standardized query and params
  Map<String, dynamic> _buildHeaders(
    Map<String, dynamic> query,
    Map<String, dynamic> params,
  ) {
    final headers = <String, dynamic>{
      ...?params['headers'] as Map<String, dynamic>?,
    };

    // X-Fields header for field selection
    if (query['fields'] != null) {
      final fields = query['fields'];
      headers['X-Fields'] =
          fields is List ? fields.join(',') : fields.toString();
    }

    // X-Filter header for filtering
    if (query['filter'] != null) {
      final filter = query['filter'];
      headers['X-Filter'] =
          filter is String ? filter : jsonEncode(filter);
    }

    return headers;
  }
}
