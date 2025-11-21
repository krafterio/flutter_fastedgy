/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' as inj;
import 'container.config.dart';

/// Global container instance (GetIt service locator)
final container = GetIt.instance;

/// Initialize the container with injectable auto-registration
///
/// This function should be called once at application startup,
/// before using any services from the container.
///
/// Example:
/// ```dart
/// void main() {
///   initializeContainer();
///   runApp(MyApp());
/// }
/// ```
@inj.InjectableInit()
void initializeContainer() => container.init();

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

// Injectable annotations aliases for easier usage
/// Mark a class as a singleton (single instance for the entire app lifetime)
///
/// Example:
/// ```dart
/// @singleton
/// class MyService {
///   // ...
/// }
/// ```
const singleton = inj.singleton;

/// Mark a class as a lazy singleton (created only when first accessed)
///
/// Example:
/// ```dart
/// @lazySingleton
/// class MyService {
///   // ...
/// }
/// ```
const lazySingleton = inj.lazySingleton;

/// Mark a class as injectable (new instance created each time)
///
/// Example:
/// ```dart
/// @injectable
/// class MyService {
///   // ...
/// }
/// ```
const injectable = inj.injectable;
