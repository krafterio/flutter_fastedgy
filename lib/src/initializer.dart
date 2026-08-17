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

import 'api/api_model_engine.dart';
import 'offline/offline_api_model_engine.dart';
import 'offline/filesystem_local_image_store.dart';
import 'offline/drift_local_store.dart';
import 'offline/conflict_store.dart';
import 'offline/offline_context_params.dart';
import 'offline/local_image_store.dart';
import 'offline/local_sequence.dart';
import 'offline/local_store.dart';
import 'offline/offline_database.dart';
import 'offline/outbox.dart';
import 'offline/pending_upload_store.dart';
import 'offline/reference_resolver.dart';
import 'offline/sync_lock.dart';
import 'offline/replica.dart';
import 'offline/replica_store.dart';
import 'offline/sync_engine.dart';
import 'sync/sync_status.dart';
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
  // a synchronizable ApiModel and read without connectivity.
  bool offline = false,
  String? offlineDbName,
  String? offlineImagesDbName,
  String? replicaDbName,
  LocalStore Function()? localStoreFactory,
  LocalImageStore Function()? localImageStoreFactory,
  ReplicaStore Function()? replicaStoreFactory,

  // Guards the outbox replay across processes: required only when several
  // instances of the app can run against the same offline database.
  SyncLock? syncLock,

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

  // Single SQLite database for all offline data — records/outbox/conflicts,
  // replica tables (`r_<model>`) and the image index — in one file. A replica
  // rebuild only DROPs its own tables, so it never touches the outbox, and
  // cross-store reads can join. Image bytes live on disk (not here).
  OfflineDatabase? offlineDb;
  OfflineDatabase sharedDb() =>
      offlineDb ??= OfflineDatabase.open(offlineDbName ?? 'data.db');

  // Offline context registry: apps register resolvers providing the values
  // of the params their resource paths declare (replica scoping, buffered
  // writes).
  if (offline && !hasService<OfflineContextParams>()) {
    container.registerSingleton<OfflineContextParams>(OfflineContextParams());
  }

  // LocalStore (opt-in): opened eagerly so offline reads work from the first
  // frame; cached records are purged on logout.
  if ((offline || localStoreFactory != null) && !hasService<LocalStore>()) {
    final localStore =
        localStoreFactory?.call() ?? DriftLocalStore(databaseOpener: sharedDb);
    await localStore.open();
    container.registerSingleton<LocalStore>(localStore);
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => localStore.clearAll(),
    );
  }

  // LocalSequence (opt-in, alongside LocalStore): the temporary ids of
  // optimistic offline creates and the counters of the placeholder templates;
  // reset on logout with the records they numbered.
  if (offline && !hasService<LocalSequence>()) {
    final localSequence = LocalSequence(databaseOpener: sharedDb);
    await localSequence.open();
    container.registerSingleton<LocalSequence>(localSequence);
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => localSequence.clearAll(),
    );
  }

  // PendingUploadStore (opt-in, alongside LocalStore): files produced offline,
  // waiting for their upload. Owned by the outbox, so only a replay (or a
  // logout) reclaims them.
  if (offline && !hasService<PendingUploadStore>()) {
    final pendingUploads = PendingUploadStore(databaseOpener: sharedDb);
    await pendingUploads.open();
    container.registerSingleton<PendingUploadStore>(pendingUploads);
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => pendingUploads.clearAll(),
    );
  }

  // LocalImageStore (opt-in, alongside LocalStore): persists the images
  // referenced by synced records (bytes on disk, index in SQLite); purged on
  // logout like the record cache.
  if ((offline || localImageStoreFactory != null) &&
      !hasService<LocalImageStore>()) {
    final localImageStore =
        localImageStoreFactory?.call() ??
        FilesystemLocalImageStore(databaseOpener: sharedDb);
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
        replicaStoreFactory?.call() ?? ReplicaStore(databaseOpener: sharedDb);
    await replicaStore.open();
    container.registerSingleton<ReplicaStore>(replicaStore);
    container.registerSingleton<Replica>(
      Replica(replicaStore, getService<MetadataProvider>()),
    );
    container.registerSingleton<ReferenceResolver>(ReferenceResolver());
    getService<Bus>().on<AuthLogoutEvent>().listen(
      (_) => getService<Replica>().clearAll(),
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

    final conflicts = ConflictStore(
      getService<LocalStore>(),
      onChanged: status.setConflicts,
    );
    container.registerSingleton<ConflictStore>(conflicts);
    status.setConflicts((await conflicts.all()).length);

    final engine = SyncEngine(
      outbox,
      getService<Fetcher>(),
      getService<Bus>(),
      localStore: getService<LocalStore>(),
      replica: hasService<Replica>() ? getService<Replica>() : null,
      status: status,
      conflicts: conflicts,
      lock: syncLock,
      // Resolves the target model of each payload field, so a temporary id is
      // only substituted within the model it was allocated for.
      metadatas: getService<MetadataProvider>(),
      uploads: hasService<PendingUploadStore>()
          ? getService<PendingUploadStore>()
          : null,
      images: hasService<LocalImageStore>()
          ? getService<LocalImageStore>()
          : null,
      online: Connectivity().onConnectivityChanged.map(
        (results) => results.any((result) => result != ConnectivityResult.none),
      ),
    );
    container.registerSingleton<SyncEngine>(engine);
    engine.start();
  }

  if (offline && !hasService<ApiModelEngineProvider>()) {
    container.registerSingleton<ApiModelEngineProvider>(
      const OfflineApiModelEngineProvider(),
    );
  }

  // StorageUploader: registered after the offline stores so it can buffer an
  // upload the server cannot receive, instead of failing.
  if (!hasService<StorageUploader>()) {
    container.registerSingleton<StorageUploader>(
      storageUploaderFactory?.call() ??
          StorageUploader(
            getService<Fetcher>(),
            prefix: storagePrefix ?? '',
            outbox: hasService<Outbox>() ? getService<Outbox>() : null,
            uploads: hasService<PendingUploadStore>()
                ? getService<PendingUploadStore>()
                : null,
            sequence: hasService<LocalSequence>()
                ? getService<LocalSequence>()
                : null,
            // Resolves a model's api_name for the buffered operation's path.
            metadatas: getService<MetadataProvider>(),
            // Keeps a buffered image displayable while it waits.
            images: hasService<LocalImageStore>()
                ? getService<LocalImageStore>()
                : null,
          ),
    );
  }
}
