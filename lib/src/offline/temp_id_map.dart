/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../metadata/models.dart';

/// Temporary→server id mappings collected while replaying an outbox, keyed by
/// the model the id belongs to.
///
/// Temporary ids are allocated per model, so `flow:-1` and `attachment:-1` are
/// two different records. Substituting by value alone would make the second
/// create of a batch overwrite the first one's mapping, silently re-pointing
/// every relation that referenced it.
class TempIdMap {
  final Map<String, Object> _entries = {};

  static String key(String scope, Object tempId) => '$scope:$tempId';

  /// Metadata name of the model a buffered operation targets.
  ///
  /// The scope has to be the metadata model name, because that is what a
  /// relation's `target` names: registering a create under the cache namespace
  /// (`/items`) would make the relation pointing at it (`target: 'item'`) look
  /// up a scope that was never written.
  ///
  /// Resolution order: the declared [model], else the model whose `api_name`
  /// matches the path's last segment (the same lookup `ApiModel` uses to find
  /// its own metadata), else [fallback] — with no metadata nothing can be
  /// remapped anyway, so any stable scope will do.
  static String scopeOf(
    String? model,
    String basePath,
    Map<String, MetadataModel>? metadatas, {
    required String fallback,
  }) {
    if (model != null) {
      return model;
    }

    final apiName = basePath.split('/').last;

    if (metadatas != null) {
      for (final candidate in metadatas.values) {
        if (candidate.apiName == apiName) {
          return candidate.name;
        }
      }
    }

    return fallback;
  }

  /// Record that [tempId] of [scope] became [serverId] server-side.
  void register(String scope, Object tempId, Object serverId) =>
      _entries[key(scope, tempId)] = serverId;

  /// The server id [tempId] of [scope] was replaced with, when known.
  Object? resolve(String scope, Object tempId) => _entries[key(scope, tempId)];

  bool get isEmpty => _entries.isEmpty;

  /// Substitute every known temporary id in [value], resolving each one against
  /// the model that field targets.
  ///
  /// [modelName] is the model [value] describes; [metadatas] resolves its
  /// fields. Descent rules, per field:
  /// - a generic reference carries its own target (`$model`, or `model` in the
  ///   write form), so it is read from the value itself;
  /// - a relation (`many2one`/`many2many`/`one2many`) targets `field.target`,
  ///   which becomes the model of that subtree — ids appear bare, inside
  ///   `{"id": …}`, or in an operation such as `["link", 12]`;
  /// - anything else (scalar, free-form JSON) is left untouched: without a
  ///   declared target there is no model to resolve against, and guessing would
  ///   corrupt values that merely happen to be negative.
  Object? remap(
    Object? value,
    String? modelName,
    Map<String, MetadataModel>? metadatas,
  ) {
    if (isEmpty || value is! Map) {
      return value;
    }

    final model = modelName == null ? null : metadatas?[modelName];

    if (model == null) {
      return value;
    }

    return {
      for (final entry in value.entries)
        entry.key: _remapField(
          entry.value,
          model.fields['${entry.key}'],
          metadatas,
        ),
    };
  }

  Object? _remapField(
    Object? value,
    MetadataField? field,
    Map<String, MetadataModel>? metadatas,
  ) {
    if (field == null) {
      return value;
    }

    if (field.type == 'reference') {
      return _remapReference(value);
    }

    final target = field.target;

    return target == null ? value : _remapRelation(value, target, metadatas);
  }

  /// Substitute the temporary ids of the generic references found anywhere in
  /// [value], without consulting any metadata.
  ///
  /// A generic reference is self-describing — it carries the model it points at
  /// — so recognising it by shape is not a guess, unlike a bare negative int.
  /// Used where no model schema is available, such as the attachment values of
  /// a buffered upload.
  Object? remapReferences(Object? value) {
    if (isEmpty) {
      return value;
    }

    if (value is List) {
      return [for (final item in value) remapReferences(item)];
    }

    if (value is! Map) {
      return value;
    }

    final remapped = _remapReference(value);

    if (remapped != value) {
      return remapped;
    }

    return {
      for (final entry in value.entries)
        entry.key: remapReferences(entry.value),
    };
  }

  // A generic reference names its own target, so the scope comes from the value
  // ("$model" is what a read returns, "model" what a write sends).
  Object? _remapReference(Object? value) {
    if (value is! Map) {
      return value;
    }

    final scope = (value[r'$model'] ?? value['model']) as String?;
    final id = value['id'];

    if (scope == null || id == null) {
      return value;
    }

    final resolved = resolve(scope, id);

    return resolved == null ? value : {...value, 'id': resolved};
  }

  Object? _remapRelation(
    Object? value,
    String target,
    Map<String, MetadataModel>? metadatas,
  ) {
    if (value is int) {
      return resolve(target, value) ?? value;
    }

    if (value is List) {
      return [
        for (final item in value) _remapRelation(item, target, metadatas),
      ];
    }

    if (value is Map) {
      // A nested object describes a record of the target model: its own id is
      // remapped in that scope, and its fields are remapped as that model.
      final remapped = remap(value, target, metadatas);
      final nested = remapped is Map
          ? Map<Object?, Object?>.from(remapped)
          : Map<Object?, Object?>.from(value);
      final id = value['id'];

      if (id != null) {
        final resolved = resolve(target, id);

        if (resolved != null) {
          nested['id'] = resolved;
        }
      }

      return nested;
    }

    return value;
  }
}
