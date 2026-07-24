/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../metadata/metadata_provider.dart';
import '../metadata/models.dart';

/// Relation kind of a schema field, mapped from the Metadata Generator type
/// names (`many2one`, `one2many`, `many2many`, `one2one`, `reference`).
enum LocalRelationKind { none, many2one, one2many, many2many, reference }

/// One field of a replicated model, derived from its [MetadataField].
class LocalFieldSchema {
  final String name;

  /// Metadata type name (`char`, `integer`, `datetime`, `many2one`…).
  final String type;

  /// Target model name for relation fields.
  final String? target;

  /// Allowed target model names of a generic `reference` field.
  final List<String>? targets;

  const LocalFieldSchema({
    required this.name,
    required this.type,
    this.target,
    this.targets,
  });

  /// Column persisting the target model name of a `reference` field.
  String get referenceModelColumn => '${name}_model';

  /// Column persisting the target id of a `reference` field.
  String get referenceIdColumn => '${name}_id';

  /// Whether this field is a geographic point (server `PointField`, PostGIS
  /// `geometry(Point)`, payload `[longitude, latitude]`): locally it
  /// materializes as the [pointLngColumn]/[pointLatColumn] REAL pair.
  bool get isPoint => type == 'point';

  /// Column persisting the longitude of a point field.
  String get pointLngColumn => '${name}_lng';

  /// Column persisting the latitude of a point field.
  String get pointLatColumn => '${name}_lat';

  /// Whether this field is an embedding vector (server `VectorField`, pgvector
  /// `VECTOR(dimensions)`, payload `[float, …]`): locally it materializes as a
  /// plain TEXT column holding the JSON array, queried through JSON1
  /// (`json_each`) by the distance operators.
  bool get isVector => type == 'vector';

  LocalRelationKind get relationKind => switch (type) {
    'many2one' || 'many2one_ref' || 'one2one' => LocalRelationKind.many2one,
    'one2many' => LocalRelationKind.one2many,
    'many2many' => LocalRelationKind.many2many,
    'reference' => LocalRelationKind.reference,
    _ => LocalRelationKind.none,
  };

  /// Whether this field materializes as a single table column (scalars and
  /// m2o ids; inverse and generic relations are resolved through other
  /// tables). The server fulltext field is metadata-only (excluded from API
  /// payloads): locally it materializes as the derived `search_value_fts_*`
  /// columns. Point fields materialize as their lng/lat column pair.
  bool get isColumn =>
      type != 'fulltext' &&
      !isPoint &&
      (relationKind == LocalRelationKind.none ||
          relationKind == LocalRelationKind.many2one);

  /// SQLite column affinity of this field.
  String get sqlAffinity => switch (type) {
    'integer' ||
    'big_integer' ||
    'small_integer' ||
    'boolean' ||
    'many2one' ||
    'many2one_ref' ||
    'one2one' => 'INTEGER',
    'float' || 'decimal' => 'REAL',
    _ => 'TEXT',
  };
}

/// Search weight of a source field, mirroring the server's
/// `SEARCH_WEIGHT_FIELD_MAP` (`fastedgy/orm/fields/field_fulltext.py`) keyed
/// by metadata type name. Explicit per-field weight overrides
/// (`searchable="A"`) are not exposed by the metadata — such fields fall back
/// to their type weight, which only shifts local ranking, never matching.
String searchWeightForType(String type) => switch (type) {
  'char' => 'a',
  'text' => 'b',
  // 'h_t_m_l' is what the server's snake_case fallback currently emits for
  // HTMLField; 'html' is the curated name once FILTER_FIELD_TYPE_NAME_MAP
  // gains an entry for it.
  'html' || 'h_t_m_l' => 'c',
  _ => 'd',
};

/// Local mirror of a server model schema, derived from the Metadata
/// Generator.
class LocalModelSchema {
  final String name;
  final String apiName;
  final Map<String, LocalFieldSchema> fields;

  /// Name of the server fulltext field (e.g. `search_value`). The field is
  /// excluded from API payloads and metadata fields: locally it materializes
  /// as the `search_value_fts_*` derived columns and their FTS5 index.
  final String? searchField;

  /// Fulltext source fields → search weight (`a`–`d`).
  final Map<String, String> searchWeights;

  const LocalModelSchema({
    required this.name,
    required this.apiName,
    required this.fields,
    this.searchField,
    this.searchWeights = const {},
  });

  bool get searchable => searchField != null && searchWeights.isNotEmpty;

  /// Fingerprint of the fulltext configuration: any change triggers a local
  /// recompute of the derived search columns from `_raw` (never a resync).
  String get searchFingerprint {
    if (!searchable) {
      return '';
    }

    final sources =
        searchWeights.entries.map((e) => '${e.key}=${e.value}').toList()
          ..sort();

    return '$searchField:${sources.join(',')}';
  }

  Iterable<LocalFieldSchema> get columns =>
      fields.values.where((field) => field.isColumn);

  /// Generic `reference` fields, persisted as a model/id column pair.
  Iterable<LocalFieldSchema> get references => fields.values.where(
    (field) => field.relationKind == LocalRelationKind.reference,
  );

  /// Direct many2many fields, persisted in pivot tables.
  Iterable<LocalFieldSchema> get manyToMany => fields.values.where(
    (field) =>
        field.relationKind == LocalRelationKind.many2many &&
        field.target != null,
  );

  /// Geographic point fields, persisted as a lng/lat REAL column pair.
  Iterable<LocalFieldSchema> get points =>
      fields.values.where((field) => field.isPoint);

  /// Stable schema fingerprint driving the auto-migrator: any change in the
  /// column set (name, type or target) changes it.
  String get fingerprint {
    final parts = [
      ...columns.map(
        (field) => '${field.name}:${field.type}:${field.target ?? ''}',
      ),
      ...references.map(
        (field) =>
            '${field.name}:reference:${(field.targets ?? const []).join(',')}',
      ),
      ...manyToMany.map((field) => '${field.name}:many2many:${field.target}'),
      ...points.map((field) => '${field.name}:point'),
    ].toList()..sort();

    return parts.join('|');
  }
}

/// The replicated subset of the server schema, materialized from
/// `/dataset/metadatas` — no manual duplication: field types, m2o targets and
/// o2m/m2m inverses all come from the Metadata Generator.
class LocalSchema {
  final Map<String, LocalModelSchema> models;

  const LocalSchema(this.models);

  /// Build the schema from already-parsed [MetadataModel]s, keeping only
  /// [modelNames] when provided.
  factory LocalSchema.fromModels(
    Map<String, MetadataModel> metadatas, {
    Iterable<String>? modelNames,
  }) {
    final names = modelNames ?? metadatas.keys;
    final models = <String, LocalModelSchema>{};

    for (final name in names) {
      final metadata = metadatas[name];

      if (metadata == null) {
        continue;
      }

      models[name] = LocalModelSchema(
        name: metadata.name,
        apiName: metadata.apiName,
        fields: metadata.fields.map(
          (fieldName, field) => MapEntry(
            fieldName,
            LocalFieldSchema(
              name: fieldName,
              type: field.type,
              target: field.target,
              targets: field.targets,
            ),
          ),
        ),
        searchField: metadata.searchField,
        searchWeights: {
          for (final fieldName in metadata.searchableFields)
            if (metadata.fields[fieldName] != null)
              fieldName: searchWeightForType(metadata.fields[fieldName]!.type),
        },
      );
    }

    return LocalSchema(models);
  }

  /// Build the schema of [modelNames] (metadata names, e.g. `workspace_user`)
  /// from the metadata service. Unknown models are skipped (server not
  /// exposing them yet); returns null when metadata are unavailable.
  static Future<LocalSchema?> fromMetadata(
    MetadataProvider provider, {
    required Iterable<String> modelNames,
  }) async {
    final metadatas = await provider.getMetadatas();

    if (metadatas == null) {
      return null;
    }

    return LocalSchema.fromModels(metadatas, modelNames: modelNames);
  }

  /// Resolve the reverse m2o field backing the [o2mField] inverse relation of
  /// [model]: the single m2o field of the target model pointing back.
  ///
  /// Returns null when the target model is not replicated or when several
  /// FKs point back (ambiguous — needs an explicit declaration).
  String? resolveReverseField(String model, String o2mField) {
    final field = models[model]?.fields[o2mField];

    if (field == null || field.relationKind != LocalRelationKind.one2many) {
      return null;
    }

    final target = models[field.target];

    if (target == null) {
      return null;
    }

    final candidates = target.fields.values
        .where(
          (f) =>
              f.relationKind == LocalRelationKind.many2one && f.target == model,
        )
        .toList();

    return candidates.length == 1 ? candidates.single.name : null;
  }

  /// Resolve the generic `reference` field backing the [o2mField] inverse
  /// relation of [model]: the single reference field of the target whose
  /// allowed targets include [model].
  LocalFieldSchema? resolveGenericReverse(String model, String o2mField) {
    final field = models[model]?.fields[o2mField];

    if (field == null || field.relationKind != LocalRelationKind.one2many) {
      return null;
    }

    final target = models[field.target];

    if (target == null) {
      return null;
    }

    final candidates = target.references
        .where((f) => (f.targets ?? const []).contains(model))
        .toList();

    return candidates.length == 1 ? candidates.single : null;
  }
}
