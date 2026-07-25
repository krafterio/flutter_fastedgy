/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'models.dart';

/// Abstract metadata provider
///
/// This interface defines the contract for metadata providers.
/// Apps can extend this to implement custom metadata logic.
///
/// Example:
/// ```dart
/// class AppMetadataProvider implements MetadataProvider {
///   @override
///   Future<void> fetchMetadatas() async {
///     // Custom metadata fetching logic
///   }
///
///   // Custom methods
///   Future<void> preloadMetadata(String modelName) async {
///     // Preload specific metadata
///   }
/// }
///
/// // Register in main.dart
/// await initializeFastEdgy(
///   metadataProviderFactory: () => AppMetadataProvider(),
/// );
/// ```
abstract class MetadataProvider {
  /// Fetch all metadata from the API
  ///
  /// This forces a refresh of all cached metadata.
  Future<void> fetchMetadatas();

  /// Get all metadata (lazy loading)
  ///
  /// If metadata is not cached, it will be fetched automatically.
  /// Returns null if the user is not authenticated or if fetch failed.
  Future<Map<String, MetadataModel>?> getMetadatas();

  /// Get metadata for a specific model
  ///
  /// If metadata is not cached, it will be fetched automatically.
  /// Returns null if the model is not found or if fetch failed.
  Future<MetadataModel?> getMetadata(String modelName);

  /// Get the loading state
  bool get loading;

  /// Get the error state
  dynamic get error;

  /// Get the current prefix
  String? get prefix;

  /// Bucket the metadata currently belong to: the [prefix] with its context
  /// params substituted (`/{workspace}` → `/acme`), so a consumer caching
  /// anything derived from them can tell one tenant's schema from another's.
  ///
  /// Empty for a prefix-less provider, and while a param is unresolved.
  String get scope => '';

  /// Set the prefix for metadata API calls
  ///
  /// Example: `/agent`, `/admin`, etc.
  void setPrefix(String? newPrefix);
}
