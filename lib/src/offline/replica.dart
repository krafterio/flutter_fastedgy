/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../metadata/metadata_provider.dart';
import 'local_schema.dart';
import 'replica_store.dart';

/// Entry point of the model replication: lazily materializes the
/// [LocalSchema] from the metadata service (mirrored offline) and ensures
/// each replicated model's table (creating or auto-migrating it) once per
/// session.
class Replica {
  final ReplicaStore store;
  final Future<LocalSchema?> Function() _schemaLoader;
  LocalSchema? _schema;
  final Set<String> _ensured = {};

  /// Materialization and per-model migrations in flight, shared by their
  /// concurrent callers. The tenant data syncs several models at once, so
  /// caching the result alone would let each of them load the schema — and
  /// migrate the same table — on its own.
  Future<LocalSchema?>? _loadingSchema;
  final Map<String, Future<bool>> _ensuring = {};

  Replica(ReplicaStore store, MetadataProvider metadata)
    : this._(store, () async {
        final metadatas = await metadata.getMetadatas();

        return metadatas == null ? null : LocalSchema.fromModels(metadatas);
      });

  /// Test seam: a replica with a fixed schema.
  Replica.withSchema(ReplicaStore store, LocalSchema schema)
    : this._(store, () async => schema);

  Replica._(this.store, this._schemaLoader);

  /// The materialized schema, or null while the metadata are unavailable
  /// (never fetched and no offline mirror yet).
  ///
  /// The loader is cleared on completion, so a materialization that found no
  /// metadata (first launch offline) is retried on the next call rather than
  /// answering null for the rest of the session.
  Future<LocalSchema?> schema() async =>
      _schema ??= await (_loadingSchema ??= _schemaLoader().whenComplete(() {
        _loadingSchema = null;
      }));

  /// Ensure the table of [model] exists and matches the schema; returns true
  /// when the model has no usable local data (created or rebuilt) and must
  /// be resynced from the server.
  ///
  /// Concurrent callers for the same model share one migration and read the
  /// same verdict; once it is done the model is ensured for the session.
  Future<bool> ensure(String model) async {
    final schema = await this.schema();
    final modelSchema = schema?.models[model];

    if (modelSchema == null) {
      throw StateError(
        'Model "$model" is not available in the local schema '
        '(metadata unavailable or model unknown)',
      );
    }

    if (_ensured.contains(model)) {
      return false;
    }

    return _ensuring[model] ??= store
        .ensureModel(modelSchema)
        .then((migration) {
          _ensured.add(model);

          return migration.needsSync;
        })
        .whenComplete(() {
          _ensuring.remove(model);
        });
  }

  /// Purge every replicated model (logout): drops the tables and forgets the
  /// ensured models and the materialized schema in one move — a purge
  /// without the forget would leave [ensure] answering for dropped tables.
  Future<void> clearAll() async {
    await store.clearAll();
    _ensured.clear();
    _ensuring.clear();
    _schema = null;
    _loadingSchema = null;
  }
}
