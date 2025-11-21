/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
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
@InjectableInit()
void initializeContainer() => container.init();

/// Register a singleton instance in the container
///
/// Example:
/// ```dart
/// registerSingleton<EventBus>(EventBus());
/// ```
void registerSingleton<T extends Object>(T instance) {
  container.registerSingleton<T>(instance);
}

/// Register a lazy singleton factory in the container
///
/// The factory is called only once, the first time the service is requested.
///
/// Example:
/// ```dart
/// registerLazySingleton<ApiClient>(() => ApiClient());
/// ```
void registerLazySingleton<T extends Object>(T Function() factory) {
  container.registerLazySingleton<T>(factory);
}

/// Register a factory in the container
///
/// A new instance is created each time the service is requested.
///
/// Example:
/// ```dart
/// registerFactory<UserRepository>(() => UserRepository());
/// ```
void registerFactory<T extends Object>(T Function() factory) {
  container.registerFactory<T>(factory);
}

/// Get a service from the container
///
/// Example:
/// ```dart
/// final eventBus = getService<EventBus>();
/// ```
T getService<T extends Object>() {
  return container.get<T>();
}

/// Check if a service is registered in the container
bool isRegistered<T extends Object>() {
  return container.isRegistered<T>();
}

/// Reset the container (useful for testing)
void resetContainer() {
  container.reset();
}
