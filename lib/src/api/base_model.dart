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
///
///   factory Country.fromJson(Map<String, dynamic> json) {
///     return Country(json);
///   }
/// }
/// ```
abstract class DynamicSchema<T extends DynamicSchema<T>> {
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
  T setString(String name, String? value) =>
      setField<String>(name, value);

  /// Get an int field
  int? getInt(String name) => getField<int>(name);

  /// Set an int field
  T setInt(String name, int? value) => setField<int>(name, value);

  /// Get a double field
  double? getDouble(String name) => getField<double>(name);

  /// Set a double field
  T setDouble(String name, double? value) =>
      setField<double>(name, value);

  /// Get a bool field
  bool? getBool(String name) => getField<bool>(name);

  /// Set a bool field
  T setBool(String name, bool? value) => setField<bool>(name, value);

  /// Get a DateTime field (already parsed by _parseData)
  DateTime? getDateTime(String name) => getField<DateTime>(name);

  /// Set a DateTime field
  T setDateTime(String name, DateTime? value) =>
      setField<DateTime>(name, value);

  /// Get a Date-only field (DateTime with time set to midnight)
  DateTime? getDate(String name) {
    final dateTime = getDateTime(name);
    if (dateTime == null) return null;
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  /// Set a Date-only field (strips time component)
  T setDate(String name, DateTime? value) {
    if (value == null) return setField<DateTime>(name, null);
    final dateOnly = DateTime(value.year, value.month, value.day);
    return setField<DateTime>(name, dateOnly);
  }

  /// Get a List field
  List<V>? getList<V>(String name) => getField<List<V>>(name);

  /// Set a List field
  T setList<V>(String name, List<V>? value) =>
      setField<List<V>>(name, value);

  /// Get a Map field
  Map<String, dynamic>? getMap(String name) =>
      getField<Map<String, dynamic>>(name);

  /// Set a Map field
  T setMap(String name, Map<String, dynamic>? value) =>
      setField<Map<String, dynamic>>(name, value);

  /// Parse data map and convert datetime strings to DateTime objects
  static Map<String, dynamic> _parseData(Map<String, dynamic> data) {
    final parsed = <String, dynamic>{...data};

    // Parse datetime fields
    if (parsed['created_at'] is String) {
      parsed['created_at'] =
          DateTime.parse(parsed['created_at'] as String).toLocal();
    }
    if (parsed['updated_at'] is String) {
      parsed['updated_at'] =
          DateTime.parse(parsed['updated_at'] as String).toLocal();
    }

    return parsed;
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{..._data};

    // Convert DateTime objects back to ISO strings
    if (json['created_at'] is DateTime) {
      json['created_at'] = (json['created_at'] as DateTime).toIso8601String();
    }
    if (json['updated_at'] is DateTime) {
      json['updated_at'] = (json['updated_at'] as DateTime).toIso8601String();
    }

    return json;
  }

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
}
