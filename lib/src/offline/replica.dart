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
  Future<LocalSchema?> schema() async => _schema ??= await _schemaLoader();

  /// Ensure the table of [model] exists and matches the schema; returns true
  /// when the model has no usable local data (created or rebuilt) and must
  /// be resynced from the server.
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

    final migration = await store.ensureModel(modelSchema);
    _ensured.add(model);

    return migration.needsSync;
  }

  /// Purge every replicated model (logout): drops the tables and forgets the
  /// ensured models and the materialized schema in one move — a purge
  /// without the forget would leave [ensure] answering for dropped tables.
  Future<void> clearAll() async {
    await store.clearAll();
    _ensured.clear();
    _schema = null;
  }
}
