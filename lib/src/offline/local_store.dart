/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Persistent local store for server records, keyed by model then record id.
///
/// This is the storage contract of the offline layer: implementations persist
/// JSON-encodable maps (the output of `BaseModel.toJson()`) grouped under a
/// model namespace (typically the API base path, e.g. `/workspace_users`).
///
/// The default implementation is [SembastLocalStore] (SQLite file on native
/// platforms, IndexedDB on the web), but any backend can be plugged in by
/// implementing this interface and registering it in the container:
///
/// ```dart
/// await initializeFastEdgy(offline: true);
/// // or
/// await initializeFastEdgy(localStoreFactory: () => MyLocalStore());
///
/// final store = getService<LocalStore>();
/// await store.put('/users', 42, user.toJson());
/// final json = await store.get('/users', 42);
/// ```
abstract class LocalStore {
  /// Open the underlying database (idempotent).
  Future<void> open();

  /// Close the underlying database.
  Future<void> close();

  /// Get a single record by [model] namespace and [id], or null when absent.
  Future<Map<String, dynamic>?> get(String model, Object id);

  /// Get all records of a [model] namespace.
  Future<List<Map<String, dynamic>>> getAll(String model);

  /// Insert or update a single record.
  Future<void> put(String model, Object id, Map<String, dynamic> record);

  /// Insert or update several records, keyed by record id.
  Future<void> putAll(String model, Map<String, Map<String, dynamic>> records);

  /// Replace the whole [model] namespace with [records] (transactional
  /// clear + put), pruning records deleted on the server.
  Future<void> replaceAll(
    String model,
    Map<String, Map<String, dynamic>> records,
  );

  /// Delete a single record.
  Future<void> delete(String model, Object id);

  /// Delete all records of a [model] namespace.
  Future<void> clear(String model);

  /// Delete all records of all model namespaces (e.g. on logout).
  Future<void> clearAll();
}
