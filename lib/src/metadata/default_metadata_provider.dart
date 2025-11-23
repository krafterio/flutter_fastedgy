/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../fetcher/client.dart';
import '../fetcher/http_error.dart';
import '../logging/logger.dart';
import '../bus/bus.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_events.dart';
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

      // Parse metadata models
      _metadatas = data.map(
        (key, value) => MapEntry(
          key,
          MetadataModel.fromJson(value as Map<String, dynamic>),
        ),
      );

      _logger.finer('Metadata fetched successfully: ${_metadatas!.length} models');
    } on HttpError catch (e) {
      _logger.severe('Failed to fetch metadata: ${e.message}');
      _error = e;
    } catch (e, stackTrace) {
      _logger.severe('Unexpected error fetching metadata', e, stackTrace);
      _error = e;
    } finally {
      _loading = false;
    }
  }

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
