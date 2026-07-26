/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Base model class matching FastEdgy's BaseModel
///
/// This is a dynamic model that stores all fields in an internal map.
/// Known fields (id, created_at, updated_at) are accessible via getters,
/// and any additional fields can be accessed via getField/setField.
///
/// Uses self-type generic pattern (CRTP) to enable fluent interface with
/// correct return types for subclasses.
///
/// Example:
/// ```dart
/// class Country extends BaseModel<Country> {
///   Country(super.data);
///
///   // Using type-specific helpers (recommended)
///   String get name => getString('name')!;
///   set name(String value) => setString('name', value);
///
///   String get code => getString('code')!;
///   set code(String value) => setString('code', value);
///
///   int get population => getInt('population') ?? 0;
///   set population(int value) => setInt('population', value);
///
///   // Or using generic getField/setField
///   String? get description => getField<String>('description');
///   set description(String? value) => setField<String>('description', value);
/// }
/// ```
class DynamicSchema<T extends DynamicSchema<T>> {
  /// Internal storage for all fields (known and unknown)
  final Map<String, dynamic> _data;

  /// Create a schema from a data map
  /// Automatically parses DateTime fields to local timezone
  DynamicSchema(Map<String, dynamic> data) : _data = _parseData(data);

  /// Get a field value by name with type inference
  /// Returns a nullable value by default
  ///
  /// Usage:
  /// ```dart
  /// String? name = getField<String>('name');
  /// int? age = getField<int>('age');
  /// String nonNull = getField<String>('name') ?? 'default';
  /// ```
  V? getField<V>(String name) => _data[name] as V?;

  /// Set a field value by name with type safety (returns this for chaining)
  /// Accepts nullable values
  ///
  /// Usage:
  /// ```dart
  /// setField<String>('name', 'France');
  /// setField<String>('name', null);
  /// setField<int>('age', 25);
  /// ```
  T setField<V>(String name, V? value) {
    _data[name] = value;
    return this as T;
  }

  /// Check if a field exists
  bool hasField(String name) => _data.containsKey(name);

  /// Get all field names
  Iterable<String> get fieldNames => _data.keys;

  // ========== Type-specific helpers ==========

  /// Get a String field
  String? getString(String name) => getField<String>(name);

  /// Set a String field
  T setString(String name, String? value) => setField<String>(name, value);

  /// Get an int field
  int? getInt(String name) => getField<int>(name);

  /// Set an int field
  T setInt(String name, int? value) => setField<int>(name, value);

  /// Get a double field
  double? getDouble(String name) {
    final value = getField<dynamic>(name);
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Set a double field
  T setDouble(String name, double? value) => setField<double>(name, value);

  /// Get a bool field
  bool? getBool(String name) => getField<bool>(name);

  /// Set a bool field
  T setBool(String name, bool? value) => setField<bool>(name, value);

  /// Get a DateTime field
  DateTime? getDateTime(String name) {
    final value = getField<dynamic>(name);
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  /// Set a DateTime field
  T setDateTime(String name, DateTime? value) =>
      setField<DateTime>(name, value);

  /// Get a Date-only field (DateTime with time set to midnight)
  DateTime? getDate(String name) {
    final value = getField<dynamic>(name);
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return null;
  }

  /// Set a Date-only field (stored as a YYYY-MM-DD string)
  T setDate(String name, DateTime? value) {
    if (value == null) return setField<String>(name, null);
    final dateOnly =
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return setField<String>(name, dateOnly);
  }

  /// Get a List field
  List<V>? getList<V>(String name) => getField<List<V>>(name);

  /// Set a List field
  T setList<V>(String name, List<V>? value) => setField<List<V>>(name, value);

  /// Get a List of doubles field (e.g. a geographic point [lat, lon])
  ///
  /// Coerces each element from num/String, since a JSON array decodes as
  /// `List<dynamic>` (mixing int and double) and cannot be cast to
  /// `List<double>` directly.
  List<double>? getDoubleList(String name) {
    final value = getField<dynamic>(name);
    if (value is! List) return null;
    return value
        .map((e) {
          if (e is double) return e;
          if (e is num) return e.toDouble();
          if (e is String) return double.tryParse(e);
          return null;
        })
        .whereType<double>()
        .toList();
  }

  /// Set a List of doubles field
  T setDoubleList(String name, List<double>? value) =>
      setField<List<double>>(name, value);

  /// Get a List of strings field
  ///
  /// Coerces from `List<dynamic>` (how a JSON array decodes) by keeping only
  /// the string elements, since it cannot be cast to `List<String>` directly.
  List<String>? getStringList(String name) {
    final value = getField<dynamic>(name);
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }

  /// Set a List of strings field
  T setStringList(String name, List<String>? value) =>
      setField<List<String>>(name, value);

  /// Get a Map field
  Map<String, dynamic>? getMap(String name) =>
      getField<Map<String, dynamic>>(name);

  /// Set a Map field
  T setMap(String name, Map<String, dynamic>? value) =>
      setField<Map<String, dynamic>>(name, value);

  R? getRelation<R extends DynamicSchema<R>>(
    String name,
    R Function(Map<String, dynamic>) factory,
  ) {
    final value = getField<dynamic>(name);
    if (value == null) return null;
    if (value is Map<String, dynamic>) return factory(value);
    if (value is Map) return factory(Map<String, dynamic>.from(value));
    return factory({'id': value});
  }

  T setRelation(String name, Object? id) => setField(name, id);

  List<R> getRelations<R extends DynamicSchema<R>>(
    String name,
    R Function(Map<String, dynamic>) factory,
  ) {
    final value = getField<List<dynamic>>(name);
    if (value == null) return <R>[];
    return value.whereType<Map<String, dynamic>>().map(factory).toList();
  }

  T setRelations(String name, List<Object?> ids) => setField(name, ids);

  List<R> getObjectList<R>(
    String name,
    R Function(Map<String, dynamic>) factory,
  ) {
    final value = getField<List<dynamic>>(name);
    if (value == null) return <R>[];
    return value.whereType<Map<String, dynamic>>().map(factory).toList();
  }

  // ========== Generic reference (polymorphic m2o) helpers ==========

  /// Get the value of a generic reference field (FastEdgy GenericForeignKey):
  /// the serialized target record selected through X-Fields (discriminated by
  /// its `$model` key) or the staged `{model, id}` write form.
  Map<String, dynamic>? getReference(String name) => getMap(name);

  /// Get the target model name of a generic reference field (`$model` on a
  /// serialized record, `model` on a staged write form).
  String? getReferenceModel(String name) {
    final value = getMap(name);
    return (value?[r'$model'] ?? value?['model']) as String?;
  }

  /// Get the target record id of a generic reference field.
  int? getReferenceId(String name) => getMap(name)?['id'] as int?;

  /// Get the serialized target of a generic reference field as a typed model,
  /// or null when the reference is empty or points to another model.
  R? getReferenceAs<R extends DynamicSchema<R>>(
    String name,
    String model,
    R Function(Map<String, dynamic>) factory,
  ) {
    final value = getMap(name);
    if (value == null || getReferenceModel(name) != model) return null;
    return factory(value);
  }

  /// Stage a generic reference as its `{model, id}` write form
  /// (null model or id clears the reference).
  T setReference(String name, String? model, int? id) {
    if (model == null || id == null) {
      return setField<Map<String, dynamic>>(name, null);
    }
    return setMap(name, {'model': model, 'id': id});
  }

  /// Parse a single value recursively (deserialization).
  ///
  /// Field values and list elements that look like ISO datetimes are converted
  /// to [DateTime]. Map values are normalized (String keys) but their leaves are
  /// kept raw, so free-form blobs (e.g. preferences) round trip unchanged and
  /// related objects stay typed through getRelation / getObjectList.
  static dynamic _parseValue(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');
      if (isoDatePattern.hasMatch(value)) {
        return DateTime.tryParse(value)?.toLocal() ?? value;
      }
      return value;
    }

    if (value is List) {
      return value.map((item) => _parseValue(item)).toList();
    }

    if (value is Map) {
      return _normalizeKeys(value);
    }

    return value;
  }

  /// Deep-normalize container keys to String without converting leaf values.
  static dynamic _normalizeKeys(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        result[entry.key.toString()] = _normalizeKeys(entry.value);
      }
      return result;
    }
    if (value is List) {
      return value.map((item) => _normalizeKeys(item)).toList();
    }
    return value;
  }

  /// Parse data map and convert values recursively
  static Map<String, dynamic> _parseData(Map<String, dynamic> data) {
    final parsed = <String, dynamic>{};

    for (final entry in data.entries) {
      parsed[entry.key] = _parseValue(entry.value);
    }

    return parsed;
  }

  /// Dump a single value recursively (serialization)
  ///
  /// Converts:
  /// - DateTime → ISO strings
  /// - DynamicSchema → toJson()
  /// - Lists → recursively dumped lists
  /// - Maps → recursively dumped maps
  static dynamic _dumpValue(dynamic value) {
    if (value == null) {
      return null;
    }

    // Convert DateTime to ISO string
    if (value is DateTime) {
      return value.toIso8601String();
    }

    // Convert DynamicSchema to JSON
    if (value is DynamicSchema) {
      return value.toJson();
    }

    // Dump lists recursively
    if (value is List) {
      return value.map((item) => _dumpValue(item)).toList();
    }

    // Dump maps recursively
    if (value is Map) {
      final dumped = <String, dynamic>{};
      for (final entry in value.entries) {
        dumped[entry.key.toString()] = _dumpValue(entry.value);
      }
      return dumped;
    }

    // Return primitives and other types as-is
    return value;
  }

  /// Dump data map to JSON-serializable format
  static Map<String, dynamic> _dumpData(Map<String, dynamic> data) {
    final dumped = <String, dynamic>{};

    for (final entry in data.entries) {
      dumped[entry.key] = _dumpValue(entry.value);
    }

    return dumped;
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => _dumpData(_data);

  /// Get the raw data map (useful for debugging)
  Map<String, dynamic> get data => Map.unmodifiable(_data);
}

abstract class BaseModel<T extends BaseModel<T>> extends DynamicSchema<T> {
  BaseModel(super.data);

  /// Primary key (auto-generated by database)
  int? get id => _data['id'] as int?;

  /// Creation timestamp (auto-generated by database)
  DateTime? get createdAt => _data['created_at'] as DateTime?;

  /// Last update timestamp (auto-generated by database)
  DateTime? get updatedAt => _data['updated_at'] as DateTime?;

  /// True while the record exists only locally: created or updated offline and
  /// still waiting for its replay. Set by the offline engine on the mirrored
  /// record, so a list can mark the row as not yet on the server.
  bool get isOfflinePending => _data['_offline_pending'] == true;
}

class SimpleMessage extends DynamicSchema<SimpleMessage> {
  SimpleMessage(super.data);

  String get message => getString('message')!;
  set message(String value) => setString('message', value);
}
