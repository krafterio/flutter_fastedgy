/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Mixin to add workspace relationship field
///
/// Matches FastEdgy's WorkspaceableMixin. The workspace field is optional
/// as it's auto-populated by the backend based on the current context.
///
/// Example:
/// ```dart
/// class MyModel extends BaseModel<MyModel> with WorkspaceableMixin {
///   final String name;
///
///   MyModel({
///     super.id,
///     super.createdAt,
///     super.updatedAt,
///     this.workspace,
///     required this.name,
///   });
///
///   factory MyModel.fromJson(Map<String, dynamic> json) {
///     return MyModel(
///       id: json['id'] as int?,
///       // ... other base fields
///       workspace: json['workspace'],
///       name: json['name'] as String,
///     );
///   }
/// }
/// ```
mixin WorkspaceableMixin {
  /// Workspace relationship (auto-populated by backend)
  /// Can be either an int (workspace ID) or a Map (full workspace object)
  dynamic get workspace;
}

/// Mixin to add created_by and updated_by fields
///
/// Matches FastEdgy's BlameableMixin. These fields are optional as they're
/// auto-populated by the backend based on the current authenticated user.
///
/// Example:
/// ```dart
/// class MyModel extends BaseModel<MyModel> with BlameableMixin {
///   final String name;
///   @override
///   final dynamic createdBy;
///   @override
///   final dynamic updatedBy;
///
///   MyModel({
///     super.id,
///     super.createdAt,
///     super.updatedAt,
///     this.createdBy,
///     this.updatedBy,
///     required this.name,
///   });
///
///   factory MyModel.fromJson(Map<String, dynamic> json) {
///     return MyModel(
///       id: json['id'] as int?,
///       // ... other base fields
///       createdBy: json['created_by'],
///       updatedBy: json['updated_by'],
///       name: json['name'] as String,
///     );
///   }
/// }
/// ```
mixin BlameableMixin {
  /// User who created the record (auto-populated by backend)
  /// Can be either an int (user ID) or a Map (full user object)
  dynamic get createdBy;

  /// User who last updated the record (auto-populated by backend)
  /// Can be either an int (user ID) or a Map (full user object)
  dynamic get updatedBy;
}
