/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:get_it/get_it.dart';

/// Global container instance (GetIt service locator)
final container = GetIt.instance;

/// Initialize the container
///
/// This is called internally by initializeFastEdgy().
/// Apps don't need to call this directly.
void initializeContainer() {
  // Container is ready to use
  // Services are registered in initializeFastEdgy()
}

/// Retrieve an instance of type [T] from the container
///
/// Throws a [StateError] if the type [T] is not registered.
///
/// Example:
/// ```dart
/// final bus = getService<Bus>();
/// ```
T getService<T extends Object>() {
  return container.get<T>();
}

/// Check if a type [T] is registered in the container
///
/// Example:
/// ```dart
/// if (hasService<Bus>()) {
///   // Use the bus
/// }
/// ```
bool hasService<T extends Object>() {
  return container.isRegistered<T>();
}
