/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
import '../fetcher/client.dart';
import '../logging/logger.dart';
import '../metadata/metadata_provider.dart';
import 'offline_error.dart';
import 'replica.dart';

/// Resolves a reference (a `model` + `id`) to its full target record, applying
/// the offline policy driven by the target's `synchronizable` metadata flag.
///
/// A partial replica only stores the models it replicates and the snapshot a
/// parent embeds (via X-Fields); reaching the **full** target — to query
/// through it or navigate to it — goes through here:
///
/// - **synchronizable** target: served from the replica (kept in full sync
///   with the model). A gap (missing row — the target was created after the
///   last sync, or belongs to a not-yet-synced scope) is filled from the
///   server when online and stored (**gap-fill**); offline + missing → null.
/// - **non-synchronizable** target: fetched live and never stored
///   (online-only); offline → null.
///
/// The [scope] is both the replica scope and the URL prefix substituted for
/// `/{workspace}` — empty for globally-scoped models. Resolve it with
/// `getService<ReferenceResolver>()` (registered when offline is enabled).
class ReferenceResolver {
  final MetadataProvider _metadata;
  final Replica? _replica;
  final Fetcher _fetcher;

  ReferenceResolver({
    MetadataProvider? metadata,
    Replica? replica,
    Fetcher? fetcher,
  }) : _metadata = metadata ?? getService<MetadataProvider>(),
       _replica =
           replica ?? (hasService<Replica>() ? getService<Replica>() : null),
       _fetcher = fetcher ?? getService<Fetcher>();

  Future<Map<String, dynamic>?> resolve(
    String model,
    Object id, {
    String scope = '',
  }) async {
    final meta = await _metadata.getMetadata(model);
    final synchronizable = meta?.synchronizable ?? false;
    final replica = _replica;

    if (synchronizable && replica != null) {
      try {
        await replica.ensure(model);

        final local = await replica.store.getById(model, scope, id);

        if (local != null) {
          return local;
        }
      } catch (error) {
        // A broken replica must not fail the resolution: fall through to the
        // server fetch below.
        getLogger('ReferenceResolver').warning(
          'Replica lookup failed for "$model" - fetching from server: $error',
        );
      }
    }

    // Gap-fill (synchronizable, missing) or dynamic load (non-synchronizable):
    // fetch from the server; offline leaves the reference unresolved.
    final apiName = meta?.apiName;

    if (apiName == null) {
      return null;
    }

    final Map<String, dynamic> record;

    try {
      final path = scope.isEmpty ? '/$apiName/$id' : '/$scope/$apiName/$id';
      final response = await _fetcher.get(path);
      record = (response.data as Map).cast<String, dynamic>();
    } catch (error) {
      if (isOfflineError(error)) {
        return null;
      }

      rethrow;
    }

    // Only a synchronizable target is persisted (gap-fill); a dynamic target
    // stays online-only.
    if (synchronizable && replica != null) {
      final schema = await replica.schema();
      final modelSchema = schema?.models[model];

      if (modelSchema != null) {
        await replica.store.upsertAll(modelSchema, scope, [record]);
      }
    }

    return record;
  }

  /// Resolve the target of a reference [field] held by a local [record] of
  /// [model], to its full record — applying the same policy as [resolve].
  ///
  /// The target model is read from the value's `$model` (a generic reference)
  /// or from the field's `target` in the metadata (a foreign key); the id from
  /// the value's `id`. Returns null when the reference is empty or its target
  /// is unknown.
  Future<Map<String, dynamic>?> resolveField(
    String model,
    Map<String, dynamic> record,
    String field, {
    String scope = '',
  }) async {
    final value = record[field];

    if (value is! Map) {
      return null;
    }

    final id = value['id'];

    if (id == null) {
      return null;
    }

    final targetModel =
        value[r'$model'] as String? ??
        (await _metadata.getMetadata(model))?.fields[field]?.target;

    if (targetModel == null) {
      return null;
    }

    return resolve(targetModel, id as Object, scope: scope);
  }
}
