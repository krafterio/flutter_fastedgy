/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../fetcher/client.dart';
import 'api_helpers.dart';
import 'api_model.dart';
import 'api_query.dart';
import 'base_model.dart';
import 'pagination_result.dart';
import 'record_result.dart';

enum ResourceChangeType { created, updated, deleted }

class ResourceChangedEvent {
  final String basePath;
  final ResourceChangeType? type;
  final Object? id;

  /// True when the cross-instance relay re-fired this event from another
  /// process. The relay only rebroadcasts local (non-relayed) events, so this
  /// flag is what breaks the echo loop between instances.
  final bool relayed;

  /// What the write asked to change, when it said so.
  ///
  /// The keys of the payload that was sent — never everything the server ended
  /// up touching, which it does not report: a save also stamps whatever the
  /// model stamps on every write. So this answers "did the writer aim at any of
  /// this?", and a holder that reads none of these fields *and* nothing the
  /// server stamps has nothing to learn from the event.
  ///
  /// Null where the write did not say, which has to be taken as everything.
  final Set<String>? fields;

  const ResourceChangedEvent(
    this.basePath, {
    this.type,
    this.id,
    this.relayed = false,
    this.fields,
  });

  /// Whether something reading [read] has anything to learn from this event.
  ///
  /// Anything but an update always has: a row appearing or going changes a list
  /// whatever its columns are. An update with nothing declared has too — an
  /// event that says nothing means everything.
  ///
  /// A dotted path counts either way round, `project` moving being news to a
  /// holder reading `project.name`.
  /// Reading nothing in particular is reading everything: a holder that has not
  /// said what it is after cannot be told it is not concerned.
  bool touches(Iterable<String> read) {
    final moved = fields;

    if (type != ResourceChangeType.updated ||
        moved == null ||
        moved.isEmpty ||
        read.isEmpty) {
      return true;
    }

    return read.any(
      (one) => moved.any(
        (other) =>
            one == other ||
            one.startsWith('$other.') ||
            other.startsWith('$one.'),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'basePath': basePath,
    if (type != null) 'type': type!.name,
    if (id != null) 'id': id,
    if (fields != null) 'fields': fields!.toList(),
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
      json['basePath'] as String,
      type: type,
      id: json['id'],
      relayed: relayed,
      fields: fields is List ? {for (final field in fields) '$field'} : null,
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
      headers: headers,
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
      headers: headers,
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
      headers: headers,
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
