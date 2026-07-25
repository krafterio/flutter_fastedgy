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

  Map<String, MetadataModel>? _metadatas;
  bool _loading = false;
  dynamic _error;
  String? _prefix;

  DefaultMetadataProvider(this._fetcher, this._authProvider, this._bus) {
    _setupEventListeners();
  }

  void _setupEventListeners() {
    _bus.on<AuthLogoutEvent>().listen((_) {
      _logger.fine('Clearing metadata cache on logout');
      _metadatas = null;
      _error = null;
    });
  }

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

  @override
  Future<void> fetchMetadatas() async {
    final isAuth = await _authProvider.isAuthenticated();
    if (!isAuth) {
      _logger.fine('User not authenticated, skipping metadata fetch');
      return;
    }

    _loading = true;
    _error = null;

    try {
      final url = '${_prefix ?? ''}/dataset/metadatas';
      _logger.finer('Fetching metadata from $url');

      final response = await _fetcher.get(url);
      final data = response.data as Map<String, dynamic>;

      _metadatas = _parse(data);
      await _persist(data);

      _logger.finer(
        'Metadata fetched successfully: ${_metadatas!.length} models',
      );
    } on HttpError catch (e) {
      if (isServerUnavailable(e) && await _restore()) {
        _logger.fine('Metadata served from the local mirror');
      } else {
        _logger.severe('Failed to fetch metadata: ${e.message}');
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
  Future<void> _persist(Map<String, dynamic> data) async {
    await _localStore?.put(_cacheModel, _cacheKey, data);
  }

  Future<bool> _restore() async {
    final data = await _localStore?.get(_cacheModel, _cacheKey);

    if (data == null) {
      return false;
    }

    _metadatas = _parse(data);

    return true;
  }

  static const _cacheModel = '/dataset/metadatas';
  static const _cacheKey = 'metadatas';

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async {
    if (_metadatas == null) {
      await fetchMetadatas();
    }

    return _metadatas;
  }

  @override
  Future<MetadataModel?> getMetadata(String modelName) async {
    final metadatas = await getMetadatas();
    return metadatas?[modelName];
  }
}
