/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:get_it/get_it.dart';

/// The service container: GetIt, through the members applications use, so
/// that it sees every registration.
///
/// What [getService] finds under a type other than the one a service was
/// registered under is remembered, none included, until a service is
/// registered or removed: a lookup does not search the container each time.
class ServiceContainer {
  ServiceContainer(this._services);

  final GetIt _services;

  /// The services found for a type none was registered under, by that type.
  final _found = <Type, Set<Object>>{};

  T registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    bool? signalsReady,
    DisposingFunc<T>? dispose,
  }) {
    _found.clear();

    return _services.registerSingleton<T>(
      instance,
      instanceName: instanceName,
      signalsReady: signalsReady,
      dispose: dispose,
    );
  }

  void registerLazySingleton<T extends Object>(
    FactoryFunc<T> factoryFunc, {
    String? instanceName,
    DisposingFunc<T>? dispose,
    void Function(T instance)? onCreated,
    bool useWeakReference = false,
  }) {
    _found.clear();
    _services.registerLazySingleton<T>(
      factoryFunc,
      instanceName: instanceName,
      dispose: dispose,
      onCreated: onCreated,
      useWeakReference: useWeakReference,
    );
  }

  void registerFactory<T extends Object>(
    FactoryFunc<T> factoryFunc, {
    String? instanceName,
  }) {
    _found.clear();
    _services.registerFactory<T>(factoryFunc, instanceName: instanceName);
  }

  FutureOr unregister<T extends Object>({
    Object? instance,
    String? instanceName,
    FutureOr Function(T)? disposingFunction,
    bool ignoreReferenceCount = false,
  }) {
    _found.clear();

    return _services.unregister<T>(
      instance: instance,
      instanceName: instanceName,
      disposingFunction: disposingFunction,
      ignoreReferenceCount: ignoreReferenceCount,
    );
  }

  Future<void> reset({bool dispose = true}) {
    _found.clear();

    return _services.reset(dispose: dispose);
  }

  T get<T extends Object>({
    dynamic param1,
    dynamic param2,
    String? instanceName,
    Type? type,
  }) => _services.get<T>(
    param1: param1,
    param2: param2,
    instanceName: instanceName,
    type: type,
  );

  bool isRegistered<T extends Object>({
    Object? instance,
    String? instanceName,
    Type? type,
  }) => _services.isRegistered<T>(
    instance: instance,
    instanceName: instanceName,
    type: type,
  );

  List<T> findAll<T extends Object>({
    bool includeSubtypes = true,
    bool inAllScopes = false,
    String? onlyInScope,
    bool includeMatchedByRegistrationType = true,
    bool includeMatchedByInstance = true,
    bool instantiateLazySingletons = false,
    bool callFactories = false,
  }) => _services.findAll<T>(
    includeSubtypes: includeSubtypes,
    inAllScopes: inAllScopes,
    onlyInScope: onlyInScope,
    includeMatchedByRegistrationType: includeMatchedByRegistrationType,
    includeMatchedByInstance: includeMatchedByInstance,
    instantiateLazySingletons: instantiateLazySingletons,
    callFactories: callFactories,
  );

  /// The services that are a [T] without being registered as one, once each
  /// (one instance registered under two types is still one service), searched
  /// once until a registration changes.
  Set<Object> _servicesOf<T extends Object>() =>
      _found[T] ??= _services.findAll<T>().toSet();
}

/// Global container instance
final container = ServiceContainer(GetIt.instance);

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
/// A service is also found under a type other than the one it was registered
/// under, when it is the only one to be a [T]: an application's subclass
/// registered under the package's type (`AppAuthProvider` under
/// `AuthProvider`) comes back as itself, with no cast and no second
/// registration, and the other way round. What is found is remembered until a
/// service is registered or removed.
///
/// Throws a [StateError] if no service is a [T], or if several are.
///
/// Example:
/// ```dart
/// final bus = getService<Bus>();
/// ```
T getService<T extends Object>() {
  if (container.isRegistered<T>()) {
    return container.get<T>();
  }

  final found = container._servicesOf<T>();

  if (found.length > 1) {
    throw StateError(
      'Several registered services are a $T: register the one to use as $T',
    );
  }

  return found.isEmpty ? container.get<T>() : found.single as T;
}

/// Check if a service is a [T], registered as such or not (see [getService])
///
/// Example:
/// ```dart
/// if (hasService<Bus>()) {
///   // Use the bus
/// }
/// ```
bool hasService<T extends Object>() {
  return container.isRegistered<T>() || container._servicesOf<T>().isNotEmpty;
}
