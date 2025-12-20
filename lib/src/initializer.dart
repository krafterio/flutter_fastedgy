/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'container/container.dart';
import 'i18n/i18n.dart';
import 'logging/logger.dart';
import 'auth/auth_provider.dart';
import 'auth/default_auth_provider.dart';
import 'auth/token_storage.dart';
import 'fetcher/client.dart';
import 'bus/bus.dart';
import 'metadata/metadata_provider.dart';
import 'metadata/default_metadata_provider.dart';
import 'image/image_cache.dart';
import 'storage/storage_downloader.dart';
import 'storage/storage_uploader.dart';

/// Initialize FastEdgy with default configuration
///
/// This function initializes:
/// - Environment variables from .env file
/// - Dependency injection container
/// - Logger system
/// - Internationalization (i18n)
/// - All core services (Bus, TokenStorage, etc.)
/// - Authentication provider (default or custom)
///
/// Factory functions are called in order, allowing dependencies to be resolved.
///
/// Example:
/// ```dart
/// // Default usage
/// await initializeFastEdgy();
///
/// // With custom API interceptors
/// await initializeFastEdgy(
///   apiInterceptors: [
///     InterceptorConfig(MyCustomInterceptor(), priority: 100),
///     OtherCustomInterceptor(), // priority = 100 by default
///   ],
/// );
///
/// // With custom services
/// await initializeFastEdgy(
///   busFactory: () => MyCustomBus(),
///   tokenStorageFactory: () => MyCustomTokenStorage(),
///   authProviderFactory: () => MyCustomAuthProvider(),
/// );
/// ```
Future<void> initializeFastEdgy({
  String? envFile,
  Level? logLevel,

  // API interceptors (List<InterceptorConfig> or List<Interceptor>)
  List<dynamic>? apiInterceptors,

  // Image cache configuration
  int? imageCacheMaxEntries,
  int? imageCacheMaxSizeBytes,

  // Core services factories (overridable)
  Bus Function()? busFactory,
  TokenStorage Function()? tokenStorageFactory,
  Fetcher Function()? fetcherFactory,
  AuthProvider Function()? authProviderFactory,
  MetadataProvider Function()? metadataProviderFactory,
  ImageCache Function()? imageCacheFactory,
  StorageDownloader Function()? storageDownloaderFactory,
  StorageUploader Function()? storageUploaderFactory,
}) async {
  await dotenv.load(fileName: envFile ?? '.env');

  // Initialize container
  initializeContainer();

  // Register core services in order (respecting dependencies)

  // Bus
  if (!hasService<Bus>()) {
    container.registerSingleton<Bus>(
      busFactory?.call() ?? Bus(),
    );
  }

  // TokenStorage
  if (!hasService<TokenStorage>()) {
    container.registerSingleton<TokenStorage>(
      tokenStorageFactory?.call() ?? TokenStorage(),
    );
  }

  // Fetcher
  if (!hasService<Fetcher>()) {
    container.registerSingleton<Fetcher>(
      fetcherFactory?.call() ??
          Fetcher.create(customInterceptors: apiInterceptors),
    );
  }

  // i18n
  initializeLogger(logLevel: logLevel);
  await initializeI18n();

  // AuthProvider
  if (!hasService<AuthProvider>()) {
    container.registerSingleton<AuthProvider>(
      authProviderFactory?.call() ??
          DefaultAuthProvider(
            getService<Fetcher>(),
            getService<TokenStorage>(),
            getService<Bus>(),
          ),
    );
  }

  // MetadataProvider
  if (!hasService<MetadataProvider>()) {
    container.registerSingleton<MetadataProvider>(
      metadataProviderFactory?.call() ??
          DefaultMetadataProvider(
            getService<Fetcher>(),
            getService<AuthProvider>(),
            getService<Bus>(),
          ),
    );
  }

  // ImageCache
  if (!hasService<ImageCache>()) {
    container.registerSingleton<ImageCache>(
      imageCacheFactory?.call() ??
          ImageCache(
            getService<Bus>(),
            maxCacheEntries: imageCacheMaxEntries ?? 150,
            maxCacheSizeBytes: imageCacheMaxSizeBytes ?? 50 * 1024 * 1024,
          ),
    );
  }

  // StorageDownloader
  if (!hasService<StorageDownloader>()) {
    container.registerSingleton<StorageDownloader>(
      storageDownloaderFactory?.call() ??
          StorageDownloader(getService<Fetcher>()),
    );
  }

  // StorageUploader
  if (!hasService<StorageUploader>()) {
    container.registerSingleton<StorageUploader>(
      storageUploaderFactory?.call() ??
          StorageUploader(getService<Fetcher>()),
    );
  }
}
