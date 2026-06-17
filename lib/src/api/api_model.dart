/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../bus/bus.dart';
import '../fetcher/client.dart';
import '../container/container.dart';
import 'base_model.dart';
import 'api_helpers.dart';
import 'pagination_result.dart';
import 'api_query.dart';

enum ResourceChangeType { created, updated, deleted }

class ResourceChangedEvent {
  final String basePath;
  final ResourceChangeType? type;
  final Object? id;
  const ResourceChangedEvent(this.basePath, {this.type, this.id});
}

enum ApiAction {
  list,
  get,
  create,
  update,
  delete,
  export,
  import,
  importTemplate,
}

/// Base class for API Models
///
/// Provides CRUD operations for a REST API resource.
/// Similar to vue-fastedgy's useApiModel.
///
/// Example:
/// ```dart
/// class User extends BaseModel<User> {
///   User(super.data);
///
///   String get name => getString('name')!;
///   set name(String value) => setString('name', value);
///
///   String get email => getString('email')!;
///   set email(String value) => setString('email', value);
/// }
///
/// class UserApi extends ApiModel<User> {
///   UserApi() : super('/users');
/// }
///
/// // Usage
/// final userApi = UserApi();
/// final users = await userApi.list(params: {'page': 1, 'limit': 25});
/// final user = await userApi.get(123); // or '123'
/// final created = await userApi.create({'name': 'John', 'email': 'john@example.com'});
/// ```
abstract class ApiModel<T extends BaseModel<T>> {
  /// The base path for this resource (e.g., '/users')
  final String basePath;

  /// The HTTP client used for requests
  final Fetcher _fetcher;

  Set<ApiAction> get disabledActions => {};

  /// Create an API model for a specific resource
  ///
  /// [basePath] is the base URL path for this resource (e.g., '/users')
  /// [fetcher] is optional; if not provided, uses the global Fetcher from DI
  ApiModel(this.basePath, {Fetcher? fetcher})
    : _fetcher = fetcher ?? getService<Fetcher>();

  /// Convert JSON to model instance
  ///
  /// Must be implemented by subclasses.
  T fromJson(Map<String, dynamic> json) => DynamicSchema<T>(json) as T;

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
    if (disabledActions.contains(ApiAction.list)) {
      throw Exception('List action is not available for this model');
    }

    final queryMap = query?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final response = await _fetcher.get(
      basePath,
      params: ApiHelpers.buildQueryParams(queryMap),
      headers: ApiHelpers.buildHeaders(
        queryMap,
        extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
      ),
    );

    return PaginationResult.fromJson(response.data, fromJson);
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
  Future<T> get(Object id, {FieldsOptions? options, ApiParams? params}) async {
    if (disabledActions.contains(ApiAction.get)) {
      throw Exception('Get action is not available for this model');
    }

    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = ApiHelpers.buildHeaders(
      optionsMap,
      extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
    );

    final response = await _fetcher.get(
      '$basePath/${id.toString()}',
      headers: headers,
    );

    return fromJson(response.data);
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
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    if (disabledActions.contains(ApiAction.create)) {
      throw Exception('Create action is not available for this model');
    }

    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = ApiHelpers.buildHeaders(
      optionsMap,
      extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
    );

    final response = await _fetcher.post(
      basePath,
      payload.toJson(),
      headers: headers,
    );

    final entity = fromJson(response.data);
    notifyChanged(ResourceChangeType.created, entity.id);
    return entity;
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
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    if (disabledActions.contains(ApiAction.update)) {
      throw Exception('Update action is not available for this model');
    }

    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = ApiHelpers.buildHeaders(
      optionsMap,
      extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
    );

    final response = await _fetcher.patch(
      '$basePath/${id.toString()}',
      payload.toJson(),
      headers: headers,
    );

    notifyChanged(ResourceChangeType.updated, id);
    return fromJson(response.data);
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
  Future<void> delete(Object id, {ApiParams? params}) async {
    if (disabledActions.contains(ApiAction.delete)) {
      throw Exception('Delete action is not available for this model');
    }

    final paramsMap = params?.toMap() ?? {};
    final headers = paramsMap['headers'] as Map<String, dynamic>?;

    await _fetcher.delete('$basePath/${id.toString()}', headers: headers);
    notifyChanged(ResourceChangeType.deleted, id);
  }

  void notifyChanged([ResourceChangeType? type, Object? id]) =>
      getService<Bus>().fire(ResourceChangedEvent(basePath, type: type, id: id));

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
  Future<Response> export({ExportQuery? query, ApiParams? params}) async {
    if (disabledActions.contains(ApiAction.export)) {
      throw Exception('Export action is not available for this model');
    }

    final queryMap = query?.toMap() ?? {};
    if (queryMap['format'] == null) {
      queryMap['format'] = 'csv';
    }

    final paramsMap = params?.toMap() ?? {};

    return _fetcher.get(
      '$basePath/export',
      params: ApiHelpers.buildQueryParams(queryMap),
      headers: ApiHelpers.buildHeaders(
        queryMap,
        extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
      ),
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
    if (disabledActions.contains(ApiAction.import)) {
      throw Exception('Import action is not available for this model');
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(file, filename: fileName),
    });

    final paramsMap = params?.toMap() ?? {};
    final headers = paramsMap['headers'] as Map<String, dynamic>?;

    return _fetcher.post('$basePath/import', formData, headers: headers);
  }

  /// Download import template
  ///
  /// [query] includes format and fields selection
  /// [params] includes prefix and headers overrides
  ///
  /// Returns the raw response data (typically bytes for files)
  ///
  /// Example:
  /// ```dart
  /// final response = await api.importTemplate(
  ///   query: ImportTemplateQuery(
  ///     format: 'xlsx',
  ///     fields: ['id', 'name'],
  ///   ),
  /// );
  /// ```
  Future<Response> importTemplate({
    ImportTemplateQuery? query,
    ApiParams? params,
  }) async {
    if (disabledActions.contains(ApiAction.importTemplate)) {
      throw Exception('Import template action is not available for this model');
    }

    final queryMap = query?.toMap() ?? {};
    if (queryMap['format'] == null) {
      queryMap['format'] = 'xlsx';
    }

    final paramsMap = params?.toMap() ?? {};

    return _fetcher.get(
      '$basePath/import/template',
      params: ApiHelpers.buildQueryParams(queryMap),
      headers: ApiHelpers.buildHeaders(
        queryMap,
        extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
      ),
      responseType: ResponseType.bytes,
    );
  }
}

// Generic base model and api model
class GenericBaseModel extends BaseModel<GenericBaseModel> {
  GenericBaseModel(super.data);
}

class GenericApiModel extends ApiModel<GenericBaseModel> {
  GenericApiModel(super.basePath, {super.fetcher});
}

GenericApiModel useGenericApiModel(String basePath) =>
    GenericApiModel(basePath);
