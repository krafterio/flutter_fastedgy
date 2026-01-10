/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'base_model.dart';

/// Mixin to add workspace relationship field
///
/// Matches FastEdgy's WorkspaceableMixin. The workspace field is optional
/// as it's auto-populated by the backend based on the current context.
///
/// Example:
/// ```dart
/// class MyModel extends BaseModel<MyModel> with WorkspaceableMixin {
///   MyModel(super.data);
///
///   String get name => getString('name')!;
///   set name(String value) => setString('name', value);
/// }
/// ```
mixin WorkspaceableMixin {
  /// Workspace relationship (auto-populated by backend)
  /// Can be either an int (workspace ID) or a Map (full workspace object)
  DynamicSchema? get workspace;
}

/// Mixin to add created_by and updated_by fields
///
/// Matches FastEdgy's BlameableMixin. These fields are optional as they're
/// auto-populated by the backend based on the current authenticated user.
///
/// Example:
/// ```dart
/// class MyModel extends BaseModel<MyModel> with BlameableMixin {
///   MyModel(super.data);
///
///   String get name => getString('name')!;
///   set name(String value) => setString('name', value);
/// }
/// ```
mixin BlameableMixin {
  /// User who created the record (auto-populated by backend)
  /// Can be either an int (user ID) or a Map (full user object)
  DynamicSchema? get createdBy;

  /// User who last updated the record (auto-populated by backend)
  /// Can be either an int (user ID) or a Map (full user object)
  DynamicSchema? get updatedBy;
}
