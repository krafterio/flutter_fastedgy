/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'app_info/models.dart';
import 'app_info/user_agent.dart';
import 'container/container.dart';
import 'i18n/i18n.dart';
import 'logging/logger.dart';
import 'auth/auth_events.dart';
import 'auth/auth_provider.dart';
import 'auth/default_auth_provider.dart';
import 'auth/token_storage.dart';
import 'fetcher/client.dart';
import 'fetcher/interceptors/user_agent_interceptor.dart';
import 'bus/bus.dart';
import 'metadata/metadata_provider.dart';
import 'metadata/default_metadata_provider.dart';
import 'image/image_cache.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'offline/drift_local_image_store.dart';
import 'offline/drift_local_store.dart';
import 'offline/local_image_store.dart';
import 'offline/local_store.dart';
import 'offline/offline_database.dart';
import 'offline/outbox.dart';
import 'offline/replica.dart';
import 'offline/replica_store.dart';
import 'offline/sync_engine.dart';
import 'offline/sync_status.dart';
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

  bool enableUserAgent = true,

  String? storagePrefix,

  // Offline local store (opt-in): when enabled, server records (and the
  // images their declared fields reference) can be mirrored locally through
  // OfflineApiModel and read without connectivity.
  bool offline = false,
  String? offlineDbName,
  String? offlineImagesDbName,
  String? replicaDbName,
  LocalStore Function()? localStoreFactory,
  LocalImageStore Function()? localImageStoreFactory,
  ReplicaStore Function()? replicaStoreFactory,

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
    container.registerSingleton<Bus>(busFactory?.call() ?? Bus());
  }

  // TokenStorage
  if (!hasService<TokenStorage>()) {
    container.registerSingleton<TokenStorage>(
      tokenStorageFactory?.call() ?? TokenStorage(),
    );
  }

  // AuthProvider (registered BEFORE Fetcher to break circular dependency)
  // The AuthProvider will retrieve the Fetcher from the container when needed
  if (!hasService<AuthProvider>()) {
    container.registerSingleton<AuthProvider>(
      authProviderFactory?.call() ??
          DefaultAuthProvider(
            null, // Fetcher will be retrieved from container
            getService<TokenStorage>(),
            getService<Bus>(),
          ),
    );
  }

  // AppInfo (loaded once from the platform and exposed via the container so
  // any consumer can access version/build info synchronously after init).
  if (!hasService<AppInfo>()) {
    container.registerSingleton<AppInfo>(await AppInfo.fromPlatform());
  }
  final appInfo = getService<AppInfo>();

  // UserAgent: standalone service built once from AppInfo + platform, registered
  // even when the interceptor is disabled so non-Dio transports (e.g. a WebSocket
  // handshake) can read the same header via getService<UserAgent>().
  if (!hasService<UserAgent>()) {
    container.registerSingleton<UserAgent>(UserAgent.fromAppInfo(appInfo));
  }
  final userAgent = getService<UserAgent>();

  // User-Agent interceptor (consumes the UserAgent service): registered in the
  // container so custom fetcherFactory callers (and any other consumer) pick it
  // up automatically via Fetcher.create.
  UserAgentInterceptor? userAgentInterceptor;
  if (enableUserAgent && !hasService<UserAgentInterceptor>()) {
    userAgentInterceptor = UserAgentInterceptor(userAgent);
    container.registerSingleton<UserAgentInterceptor>(userAgentInterceptor);
  } else if (hasService<UserAgentInterceptor>()) {
    userAgentInterceptor = getService<UserAgentInterceptor>();
  }

  // Fetcher (can now use AuthProvider for refresh token interceptor)
  if (!hasService<Fetcher>()) {
    container.registerSingleton<Fetcher>(
      fetcherFactory?.call() ??
          Fetcher.create(
            customInterceptors: apiInterceptors,
            userAgentInterceptor: userAgentInterceptor,
          ),
    );
  }

  // i18n
  initializeLogger(logLevel: logLevel);
  await initializeI18n();

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
          StorageDownloader(getService<Fetcher>(), prefix: storagePrefix ?? ''),
    );
  }

  // StorageUploader
  if (!hasService<StorageUploader>()) {
    container.registerSingleton<StorageUploader>(
      storageUploaderFactory?.call() ??
          StorageUploader(getService<Fetcher>(), prefix: storagePrefix ?? ''),
    );
  }

  // LocalStore (opt-in): opened eagerly so offline reads work from the first
  // frame; cached records are purged on logout.
  if ((offline || localStoreFactory != null) && !hasService<LocalStore>()) {
    OfflineDatabase.allowMultipleInstances();
    final localStore =
        localStoreFactory?.call() ??
        DriftLocalStore(dbName: offlineDbName ?? 'fastedgy_offline.db');
    await localStore.open();
    container.registerSingleton<LocalStore>(localStore);
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => localStore.clearAll(),
    );
  }

  // LocalImageStore (opt-in, alongside LocalStore): persists the image blobs
  // referenced by synced records; purged on logout like the record cache.
  if ((offline || localImageStoreFactory != null) &&
      !hasService<LocalImageStore>()) {
    final localImageStore =
        localImageStoreFactory?.call() ??
        DriftLocalImageStore(
          dbName: offlineImagesDbName ?? 'fastedgy_offline_images.db',
        );
    await localImageStore.open();
    container.registerSingleton<LocalImageStore>(localImageStore);
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => localImageStore.clear(),
    );
  }

  // ReplicaStore + Replica (opt-in, alongside LocalStore): normalized model
  // replication with server-parity offline queries; purged on logout.
  if ((offline || replicaStoreFactory != null) && !hasService<ReplicaStore>()) {
    final replicaStore =
        replicaStoreFactory?.call() ??
        ReplicaStore(dbName: replicaDbName ?? 'fastedgy_replica.db');
    await replicaStore.open();
    container.registerSingleton<ReplicaStore>(replicaStore);
    container.registerSingleton<Replica>(
      Replica(replicaStore, getService<MetadataProvider>()),
    );
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => replicaStore.clearAll(),
    );
  }

  // Outbox + SyncEngine (opt-in): offline writes are buffered in the local
  // store and replayed in order when connectivity comes back.
  if (offline && hasService<LocalStore>() && !hasService<Outbox>()) {
    final initialOnline = (await Connectivity().checkConnectivity()).any(
      (result) => result != ConnectivityResult.none,
    );
    final status = SyncStatus(getService<Bus>(), online: initialOnline);
    container.registerSingleton<SyncStatus>(status);

    final outbox = Outbox(
      getService<LocalStore>(),
      onChanged: status.setPending,
    );
    container.registerSingleton<Outbox>(outbox);
    status.setPending((await outbox.all()).length);

    final engine = SyncEngine(
      outbox,
      getService<Fetcher>(),
      getService<Bus>(),
      localStore: getService<LocalStore>(),
      replica: hasService<Replica>() ? getService<Replica>() : null,
      status: status,
      online: Connectivity().onConnectivityChanged.map(
        (results) => results.any((result) => result != ConnectivityResult.none),
      ),
    );
    container.registerSingleton<SyncEngine>(engine);
    engine.start();
  }
}
