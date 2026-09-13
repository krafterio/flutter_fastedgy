/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../container/container.dart';
import '../fetcher/client.dart';
import '../realtime/origin.dart';
import '../realtime/realtime_socket.dart';
import 'api_helpers.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';
import 'pagination_result.dart';
import 'record_result.dart';

enum ResourceChangeType { created, updated, deleted }

class ResourceChangedEvent {
  /// The path of the instance that fired it; an announcement has none.
  final String? basePath;

  /// The metadata name of the model, `flow`.
  final String? model;

  /// Null when nobody says what happened, which asks for a read.
  final ResourceChangeType? type;
  final Object? id;

  /// What the write moved: the keys of the payload for a write of this
  /// instance, the columns the server wrote for an announced update, stamped
  /// ones included. Null where nobody said, which reads as everything.
  final Set<String>? fields;

  /// What the server carried with the id: `model`, `id` and the columns the
  /// model declared.
  final Map<String, dynamic>? data;

  /// The client instance behind the write, when known.
  final String? origin;

  /// The server left [data] behind.
  final bool truncated;

  /// Fired by the realtime socket from an announcement, rather than by this
  /// process for a write of its own.
  final bool announced;

  /// Re-fired by the relay from another instance, which is what keeps the
  /// relay from sending it back.
  final bool relayed;

  const ResourceChangedEvent(
    this.basePath, {
    this.model,
    this.type,
    this.id,
    this.fields,
    this.data,
    this.origin,
    this.truncated = false,
    this.announced = false,
    this.relayed = false,
  });

  /// Whether this event is about what [api] holds: by model when the event
  /// names one, by path otherwise. Every api that has not resolved yet answers
  /// the bare prefix, so a named event compared by path would reach them all.
  bool isAbout(ApiModel<dynamic> api) =>
      model != null ? model == api.modelName : basePath == api.resolvedBasePath;

  /// Whether this event can be about records holding [columns]: a column it
  /// does not carry, or carries empty, says nothing, and a carried one compares
  /// as a string, an id from JSON matching one from a route.
  bool mayBeAbout(Map<String, Object?> columns) {
    final carried = data;

    if (carried == null) {
      return true;
    }

    for (final column in columns.entries) {
      final value = carried[column.key];

      if (value != null && value != '' && '$value' != '${column.value}') {
        return false;
      }
    }

    return true;
  }

  /// Whether something reading [read] has anything to learn from this event.
  ///
  /// Anything but an update always has: a row appearing or going changes a list
  /// whatever its columns are. So has an update that declared nothing, and so
  /// has a holder that reads nothing in particular.
  ///
  /// A dotted path counts either way round, `project` moving being news to a
  /// holder reading `project.name`, and so does a custom field with the `extra`
  /// column the server stores it in.
  bool touches(Iterable<String> read) {
    final moved = fields;

    if (type != ResourceChangeType.updated ||
        moved == null ||
        moved.isEmpty ||
        read.isEmpty) {
      return true;
    }

    return read.any((one) => moved.any((other) => _sameColumn(one, other)));
  }

  static const _extraColumn = 'extra';
  static const _extraFieldPrefix = 'extra_';

  static bool _sameColumn(String one, String other) =>
      one == other ||
      one.startsWith('$other.') ||
      other.startsWith('$one.') ||
      (one == _extraColumn && other.startsWith(_extraFieldPrefix)) ||
      (other == _extraColumn && one.startsWith(_extraFieldPrefix));

  Map<String, dynamic> toJson() => {
    if (basePath != null) 'basePath': basePath,
    if (model != null) 'model': model,
    if (type != null) 'type': type!.name,
    if (id != null) 'id': id,
    if (fields != null) 'fields': fields!.toList(),
    if (origin != null) 'origin': origin,
  };

  factory ResourceChangedEvent.fromJson(
    Map<String, dynamic> json, {
    bool relayed = false,
  }) {
    final typeName = json['type'] as String?;
    ResourceChangeType? type;
    for (final value in ResourceChangeType.values) {
      if (value.name == typeName) {
        type = value;
        break;
      }
    }

    final fields = json['fields'];

    return ResourceChangedEvent(
      json['basePath'] as String?,
      model: json['model'] as String?,
      type: type,
      id: json['id'],
      fields: fields is List ? {for (final field in fields) '$field'} : null,
      origin: json['origin'] as String?,
      relayed: relayed,
    );
  }
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

/// Online engine of an [ApiModel]: raw HTTP CRUD, no cache. The default
/// backend; its identity and hooks are read from [owner]. The cache methods
/// ([sync], [cachedList]…) are no-ops here and overridden by the offline
/// engine.
class ApiModelEngine<T extends BaseModel<T>> {
  final ApiModel<T> owner;

  ApiModelEngine(this.owner);

  Fetcher get fetcher => owner.fetcher;

  Future<PaginationResult<T>> list({
    ListQuery? query,
    ApiParams? params,
  }) async {
    if (owner.disabledActions.contains(ApiAction.list)) {
      throw Exception('List action is not available for this model');
    }

    final queryMap = query?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final response = await fetcher.get(
      await owner.resolvePath(),
      params: ApiHelpers.buildQueryParams(queryMap),
      headers: ApiHelpers.buildHeaders(
        queryMap,
        extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
      ),
    );

    return PaginationResult.fromJson(response.data, owner.fromJson);
  }

  /// Reads a record, routed through [getResult]: an engine that widens where a
  /// record may come from — the offline one and its mirror fallback — overrides
  /// that one alone and both stay consistent.
  Future<T> get(Object id, {FieldsOptions? options, ApiParams? params}) async =>
      (await getResult(id, options: options, params: params)).value;

  Future<RecordResult<T>> getResult(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    if (owner.disabledActions.contains(ApiAction.get)) {
      throw Exception('Get action is not available for this model');
    }

    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = ApiHelpers.buildHeaders(
      optionsMap,
      extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
    );

    final response = await fetcher.get(
      '${await owner.resolvePath()}/${id.toString()}',
      headers: headers,
    );

    return RecordResult(owner.fromJson(response.data));
  }

  /// Whether a write made while the server is unreachable buffers for a later
  /// replay instead of failing. False here: the online engine has nowhere to
  /// keep it.
  bool get bufferizesWrites => false;

  /// Stamps a write with an origin of its own, and has the socket expect its
  /// echo before the request leaves.
  Map<String, dynamic> _expectEcho(Map<String, dynamic>? headers, Object? id) {
    final origin = requestOrigin();
    final model = owner.modelName;

    if (model != null && hasService<RealtimeSocket>()) {
      getService<RealtimeSocket>().expect(origin, model, id);
    }

    return {...?headers, originHeader: origin};
  }

  Future<T> create(
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    if (owner.disabledActions.contains(ApiAction.create)) {
      throw Exception('Create action is not available for this model');
    }

    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = ApiHelpers.buildHeaders(
      optionsMap,
      extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
    );

    final response = await fetcher.post(
      await owner.resolvePath(),
      payload.toJson(),
      headers: _expectEcho(headers, null),
    );

    final entity = owner.fromJson(response.data);
    owner.notifyChanged(
      ResourceChangeType.created,
      entity.id,
      payload.toJson().keys.toSet(),
    );
    return entity;
  }

  Future<T> update(
    Object id,
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async {
    if (owner.disabledActions.contains(ApiAction.update)) {
      throw Exception('Update action is not available for this model');
    }

    final optionsMap = options?.toMap() ?? {};
    final paramsMap = params?.toMap() ?? {};

    final headers = ApiHelpers.buildHeaders(
      optionsMap,
      extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
    );

    final response = await fetcher.patch(
      '${await owner.resolvePath()}/${id.toString()}',
      payload.toJson(),
      headers: _expectEcho(headers, id),
    );

    owner.notifyChanged(
      ResourceChangeType.updated,
      id,
      payload.toJson().keys.toSet(),
    );
    return owner.fromJson(response.data);
  }

  Future<void> delete(Object id, {ApiParams? params}) async {
    if (owner.disabledActions.contains(ApiAction.delete)) {
      throw Exception('Delete action is not available for this model');
    }

    final paramsMap = params?.toMap() ?? {};
    final headers = paramsMap['headers'] as Map<String, dynamic>?;

    await fetcher.delete(
      '${await owner.resolvePath()}/${id.toString()}',
      headers: _expectEcho(headers, id),
    );
    owner.notifyChanged(ResourceChangeType.deleted, id);
  }

  Future<Response> export({ExportQuery? query, ApiParams? params}) async {
    if (owner.disabledActions.contains(ApiAction.export)) {
      throw Exception('Export action is not available for this model');
    }

    final queryMap = query?.toMap() ?? {};
    if (queryMap['format'] == null) {
      queryMap['format'] = 'csv';
    }

    final paramsMap = params?.toMap() ?? {};

    return fetcher.get(
      '${await owner.resolvePath()}/export',
      params: ApiHelpers.buildQueryParams(queryMap),
      headers: ApiHelpers.buildHeaders(
        queryMap,
        extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
      ),
      responseType: ResponseType.bytes,
    );
  }

  Future<Response> import(
    List<int> file,
    String fileName, {
    ApiParams? params,
  }) async {
    if (owner.disabledActions.contains(ApiAction.import)) {
      throw Exception('Import action is not available for this model');
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(file, filename: fileName),
    });

    final paramsMap = params?.toMap() ?? {};
    final headers = paramsMap['headers'] as Map<String, dynamic>?;

    return fetcher.post(
      '${await owner.resolvePath()}/import',
      formData,
      headers: headers,
    );
  }

  Future<Response> importTemplate({
    ImportTemplateQuery? query,
    ApiParams? params,
  }) async {
    if (owner.disabledActions.contains(ApiAction.importTemplate)) {
      throw Exception('Import template action is not available for this model');
    }

    final queryMap = query?.toMap() ?? {};
    if (queryMap['format'] == null) {
      queryMap['format'] = 'xlsx';
    }

    final paramsMap = params?.toMap() ?? {};

    return fetcher.get(
      '${await owner.resolvePath()}/import/template',
      params: ApiHelpers.buildQueryParams(queryMap),
      headers: ApiHelpers.buildHeaders(
        queryMap,
        extraHeaders: paramsMap['headers'] as Map<String, dynamic>?,
      ),
      responseType: ResponseType.bytes,
    );
  }

  Future<void> sync({ApiParams? params}) async {}

  Future<List<T>> cachedList() async => <T>[];

  Future<T?> cachedGet(Object id) async => null;

  Future<PaginationResult<T>> cachedQuery([ListQuery? query]) async =>
      PaginationResult<T>(
        items: <T>[],
        total: 0,
        limit: query?.limit ?? query?.size ?? 0,
        offset: 0,
        totalPages: 0,
      );

  Future<void> clearCache() async {}

  Stream<PaginationResult<T>> listCacheThenNetwork({
    ListQuery? query,
    ApiParams? params,
  }) async* {
    yield await list(query: query, params: params);
  }

  Stream<T> getCacheThenNetwork(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async* {
    yield await get(id, options: options, params: params);
  }
}

/// Builds the engine an [ApiModel] delegates to. `initializeFastEdgy(offline:
/// true)` swaps the default for one yielding the offline engine.
abstract class ApiModelEngineProvider {
  ApiModelEngine<T> create<T extends BaseModel<T>>(ApiModel<T> owner);
}

class DefaultApiModelEngineProvider implements ApiModelEngineProvider {
  const DefaultApiModelEngineProvider();

  @override
  ApiModelEngine<T> create<T extends BaseModel<T>>(ApiModel<T> owner) =>
      ApiModelEngine<T>(owner);
}
