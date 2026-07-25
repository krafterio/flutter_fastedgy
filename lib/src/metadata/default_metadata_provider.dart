/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
import '../fetcher/client.dart';
import '../fetcher/http_error.dart';
import '../logging/logger.dart';
import '../bus/bus.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_events.dart';
import '../offline/local_store.dart';
import '../offline/offline_context_params.dart';
import 'metadata_provider.dart';
import 'models.dart';

/// Default implementation of MetadataProvider
///
/// Provides standard FastEdgy metadata fetching with caching.
class DefaultMetadataProvider implements MetadataProvider {
  final Fetcher _fetcher;
  final AuthProvider _authProvider;
  final Bus _bus;
  final _logger = getLogger('MetadataProvider');

  bool _loading = false;
  dynamic _error;
  String? _prefix;

  /// Metadata and in-flight fetches, both keyed by [_scope].
  ///
  /// A [setPrefix] carrying a context param (`/{workspace}`) makes the payload
  /// tenant-specific, so a single slot would serve one workspace's metadata to
  /// the next. Without a prefix every entry lands under the same empty scope.
  ///
  /// The fetches are held as futures rather than as their result alone: the
  /// schema is resolved concurrently at boot — one [ApiModel] per screen, plus
  /// the replica materializing its local schema — and all of them arrive
  /// before anything is cached.
  final Map<String, Map<String, MetadataModel>> _metadatas = {};
  final Map<String, Future<void>> _fetching = {};

  DefaultMetadataProvider(this._fetcher, this._authProvider, this._bus) {
    _setupEventListeners();
  }

  void _setupEventListeners() {
    _bus.on<AuthLogoutEvent>().listen((_) {
      _logger.fine('Clearing metadata cache on logout');
      _metadatas.clear();
      _error = null;
    });
  }

  /// The prefix with its context params substituted, or null while any of them
  /// is unresolved — there is no tenant to ask the metadata of yet, and asking
  /// under the raw placeholder would only reach a route that does not exist.
  ///
  /// A resource needing to be reachable before that point declares its own
  /// `apiName` rather than reading it here.
  String? get _resolvedPrefix {
    final prefix = _prefix;

    if (prefix == null || prefix.isEmpty) {
      return '';
    }

    if (!prefix.contains('{')) {
      return prefix;
    }

    if (!hasService<OfflineContextParams>()) {
      return null;
    }

    final resolved = OfflineContextParams.substituteWith(
      prefix,
      getService<OfflineContextParams>().resolve(),
    );

    return resolved.contains('{') ? null : resolved;
  }

  /// Cache bucket the metadata belong to: two workspaces never share a slot.
  @override
  String get scope => _resolvedPrefix ?? '';

  @override
  bool get loading => _loading;

  @override
  dynamic get error => _error;

  @override
  String? get prefix => _prefix;

  @override
  void setPrefix(String? newPrefix) {
    _prefix = newPrefix;
  }

  /// Fetch the metadata of the current scope, joining the fetch already
  /// running for it rather than issuing a second one.
  ///
  /// [_fetch] never completes synchronously, so the entry is always registered
  /// before the future removes it.
  @override
  Future<void> fetchMetadatas() {
    final scope = _resolvedPrefix;

    if (scope == null) {
      _logger.fine('No tenant resolved yet, skipping metadata fetch');

      return Future.value();
    }

    return _fetching[scope] ??= _fetch(scope).whenComplete(() {
      _fetching.remove(scope);
    });
  }

  Future<void> _fetch(String scope) async {
    final isAuth = await _authProvider.isAuthenticated();
    if (!isAuth) {
      _logger.fine('User not authenticated, skipping metadata fetch');
      return;
    }

    _loading = true;
    _error = null;

    try {
      final url = '$scope/dataset/metadatas';
      _logger.finer('Fetching metadata from $url');

      final response = await _fetcher.get(url);
      final data = response.data as Map<String, dynamic>;
      final metadatas = _parse(data);

      _metadatas[scope] = metadatas;
      await _persist(scope, data);

      _logger.finer(
        'Metadata fetched successfully: ${metadatas.length} models',
      );
    } on HttpError catch (e) {
      if (isServerUnavailable(e) && await _restore(scope)) {
        _logger.fine('Metadata served from the local mirror');
      } else {
        // Nothing mirrored yet (first launch offline): the caller is told the
        // schema is missing. The log pipeline degrades an unanswered server.
        _logger.severe('Failed to fetch metadata', e);
        _error = e;
      }
    } catch (e, stackTrace) {
      _logger.severe('Unexpected error fetching metadata', e, stackTrace);
      _error = e;
    } finally {
      _loading = false;
    }
  }

  Map<String, MetadataModel> _parse(Map<String, dynamic> data) =>
      data.map<String, MetadataModel>(
        (key, value) => MapEntry(
          key,
          MetadataModel.fromJson(value as Map<String, dynamic>),
        ),
      );

  LocalStore? get _localStore =>
      hasService<LocalStore>() ? getService<LocalStore>() : null;

  // The raw payload is mirrored into the local store so the schema stays
  // available offline (LocalSchema/replica depend on it at cold boot).
  Future<void> _persist(String scope, Map<String, dynamic> data) async {
    await _localStore?.put(_cacheModel, _cacheKeyOf(scope), data);
  }

  Future<bool> _restore(String scope) async {
    final data = await _localStore?.get(_cacheModel, _cacheKeyOf(scope));

    if (data == null) {
      return false;
    }

    _metadatas[scope] = _parse(data);

    return true;
  }

  static const _cacheModel = '/dataset/metadatas';
  static const _cacheKey = 'metadatas';

  // The unscoped key is left bare, so a mirror written before the metadata
  // became tenant-scoped is still the one a prefix-less app reads.
  static String _cacheKeyOf(String scope) =>
      scope.isEmpty ? _cacheKey : '$_cacheKey:$scope';

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async {
    final scope = _resolvedPrefix;

    if (scope == null) {
      return null;
    }

    if (!_metadatas.containsKey(scope)) {
      await fetchMetadatas();
    }

    return _metadatas[scope];
  }

  @override
  Future<MetadataModel?> getMetadata(String modelName) async {
    final metadatas = await getMetadatas();
    return metadatas?[modelName];
  }
}
