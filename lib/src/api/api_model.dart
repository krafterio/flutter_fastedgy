/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
import '../metadata/metadata_provider.dart';
import '../metadata/models.dart';
import 'api_model_engine.dart';
import 'api_query.dart';
import 'base_model.dart';
import 'pagination_result.dart';
import 'record_result.dart';
import 'sync_image_field.dart';

export 'api_model_engine.dart';

/// Opaque handle to the offline services an [ApiModel] forwards to its engine;
/// the concrete implementation lives in the offline module so the facade never
/// imports it.
abstract interface class OfflineBindings {}

/// Facade for a REST API resource. Carries the resource identity and hooks and
/// delegates I/O to an [ApiModelEngine] chosen from the metadata on first use:
/// the injected provider's engine for a `synchronizable` model (offline once
/// `initializeFastEdgy(offline: true)` registers it), the online engine
/// otherwise. Never imports the offline module.
abstract class ApiModel<T extends BaseModel<T>> {
  final String basePath;
  final String? modelName;
  final Fetcher fetcher;
  final OfflineBindings? offlineBindings;

  /// Resource segment to use instead of asking the metadata for the model's
  /// `api_name`.
  ///
  /// Only needed by a resource that has to be reachable *before* any metadata
  /// are: with tenant-scoped metadata (`setPrefix('/{workspace}')`), the
  /// workspaces themselves cannot resolve their path from a payload that can
  /// only be fetched once a workspace is known.
  final String? apiName;

  String? _resolvedPath;
  ApiModelEngine<T>? _engine;

  ApiModel(
    this.basePath, {
    this.modelName,
    this.apiName,
    Fetcher? fetcher,
    this.offlineBindings,
  }) : fetcher = fetcher ?? getService<Fetcher>();

  Future<ApiModelEngine<T>> _resolveEngine() async {
    final existing = _engine;

    if (existing != null) {
      return existing;
    }

    final meta = await metadata();

    if (meta == null) {
      return ApiModelEngine<T>(this);
    }

    return _engine = meta.synchronizable
        ? _engineProvider().create<T>(this)
        : ApiModelEngine<T>(this);
  }

  static ApiModelEngineProvider _engineProvider() =>
      hasService<ApiModelEngineProvider>()
      ? getService<ApiModelEngineProvider>()
      : const DefaultApiModelEngineProvider();

  T fromJson(Map<String, dynamic> json) => DynamicSchema<T>(json) as T;

  Set<ApiAction> get disabledActions => {};

  String get cacheModel => modelName ?? basePath;

  /// X-Fields to mirror; null derives them from the metadata.
  List<String>? get syncFields => null;

  int get syncPageSize => 200;

  List<SyncImageField> get syncImageFields => const [];

  /// Metadata resolved by [modelName], else by the last [basePath] segment.
  Future<MetadataModel?> metadata() async {
    if (!hasService<MetadataProvider>()) {
      return null;
    }

    final provider = getService<MetadataProvider>();
    final name = modelName;

    if (name != null) {
      return provider.getMetadata(name);
    }

    final metadatas = await provider.getMetadatas();

    if (metadatas == null) {
      return null;
    }

    final apiName = basePath.split('/').last;

    for (final model in metadatas.values) {
      if (model.apiName == apiName) {
        return model;
      }
    }

    return null;
  }

  /// Resource path: [basePath] + the model `api_name`, taken from the declared
  /// [apiName] when there is one and read from the metadata otherwise,
  /// memoized once resolvable.
  Future<String> resolvePath() async {
    if (modelName == null) {
      return basePath;
    }

    final cached = _resolvedPath;

    if (cached != null) {
      return cached;
    }

    final declared = apiName;

    if (declared != null) {
      return _resolvedPath = _joinPath(basePath, declared);
    }

    final resolved = (await metadata())?.apiName;

    if (resolved == null) {
      return _joinPath(basePath, modelName!);
    }

    return _resolvedPath = _joinPath(basePath, resolved);
  }

  String get resolvedBasePath => _resolvedPath ?? basePath;

  static String _joinPath(String prefix, String segment) =>
      prefix.isEmpty ? '/$segment' : '$prefix/$segment';

  Future<MetadataField?> metadataField(String name) async =>
      (await metadata())?.fields[name];

  void notifyChanged([ResourceChangeType? type, Object? id]) =>
      getService<Bus>().fire(
        ResourceChangedEvent(resolvedBasePath, type: type, id: id),
      );

  Future<PaginationResult<T>> list({
    ListQuery? query,
    ApiParams? params,
  }) async => (await _resolveEngine()).list(query: query, params: params);

  Future<T> get(Object id, {FieldsOptions? options, ApiParams? params}) async =>
      (await _resolveEngine()).get(id, options: options, params: params);

  /// Same read as [get], keeping whether the local mirror answered instead of
  /// the server.
  Future<RecordResult<T>> getResult(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async =>
      (await _resolveEngine()).getResult(id, options: options, params: params);

  /// Whether a write made while the server is unreachable buffers for a later
  /// replay instead of failing — true for a synchronizable model once the
  /// offline outbox is wired.
  Future<bool> bufferizesWrites() async =>
      (await _resolveEngine()).bufferizesWrites;

  Future<T> create(
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async => (await _resolveEngine()).create(
    payload,
    options: options,
    params: params,
  );

  Future<T> update(
    Object id,
    DynamicSchema<T> payload, {
    FieldsOptions? options,
    ApiParams? params,
  }) async => (await _resolveEngine()).update(
    id,
    payload,
    options: options,
    params: params,
  );

  Future<void> delete(Object id, {ApiParams? params}) async =>
      (await _resolveEngine()).delete(id, params: params);

  Future<Response> export({ExportQuery? query, ApiParams? params}) async =>
      (await _resolveEngine()).export(query: query, params: params);

  Future<Response> import(
    List<int> file,
    String fileName, {
    ApiParams? params,
  }) async => (await _resolveEngine()).import(file, fileName, params: params);

  Future<Response> importTemplate({
    ImportTemplateQuery? query,
    ApiParams? params,
  }) async =>
      (await _resolveEngine()).importTemplate(query: query, params: params);

  Future<void> sync({ApiParams? params}) async =>
      (await _resolveEngine()).sync(params: params);

  Future<List<T>> cachedList() async => (await _resolveEngine()).cachedList();

  Future<T?> cachedGet(Object id) async =>
      (await _resolveEngine()).cachedGet(id);

  Future<PaginationResult<T>> cachedQuery([ListQuery? query]) async =>
      (await _resolveEngine()).cachedQuery(query);

  Future<void> clearCache() async => (await _resolveEngine()).clearCache();

  Stream<PaginationResult<T>> listCacheThenNetwork({
    ListQuery? query,
    ApiParams? params,
  }) async* {
    yield* (await _resolveEngine()).listCacheThenNetwork(
      query: query,
      params: params,
    );
  }

  Stream<T> getCacheThenNetwork(
    Object id, {
    FieldsOptions? options,
    ApiParams? params,
  }) async* {
    yield* (await _resolveEngine()).getCacheThenNetwork(
      id,
      options: options,
      params: params,
    );
  }
}

class GenericBaseModel extends BaseModel<GenericBaseModel> {
  GenericBaseModel(super.data);
}

class GenericApiModel extends ApiModel<GenericBaseModel> {
  GenericApiModel(super.basePath, {super.modelName, super.fetcher});
}

GenericApiModel useGenericApiModel(String basePath) =>
    GenericApiModel(basePath);
