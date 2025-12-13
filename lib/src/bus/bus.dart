/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'package:event_bus/event_bus.dart';

/// Application-wide event bus for communication between components
///
/// This is a wrapper around the event_bus package that provides
/// a simple singleton pattern for application-wide event communication.
///
/// Example usage:
/// ```dart
/// // Get from container
/// final bus = getService<Bus>();
///
/// // Fire an event
/// bus.fire(UserLoggedInEvent('user123'));
///
/// // Listen to events
/// bus.on<UserLoggedInEvent>().listen((event) {
///   print('User logged in: ${event.userId}');
/// });
///
/// // Fire and wait for async listeners
/// await bus.fireAndWait(MyAsyncEvent());
/// ```
class Bus {
  final EventBus _bus = EventBus();

  /// Fire an event to all listeners
  void fire(dynamic event) {
    _bus.fire(event);
  }

  /// Fire an event and wait for all async listeners to complete
  ///
  /// This method is useful when you need to ensure all listeners have
  /// completed their async work before continuing.
  ///
  /// The event must extend [AsyncEvent] and listeners must call
  /// [AsyncEvent.registerListener] to register their async work.
  ///
  /// Example:
  /// ```dart
  /// class MyAsyncEvent extends AsyncEvent {}
  ///
  /// // In listener
  /// bus.on<MyAsyncEvent>().listen((event) {
  ///   event.registerListener(() async {
  ///     await doSomethingAsync();
  ///   });
  /// });
  ///
  /// // Fire and wait
  /// await bus.fireAndWait(MyAsyncEvent());
  /// ```
  Future<void> fireAndWait<T>(T event) async {
    final futures = <Future<void>>[];

    final subscription = on<T>().listen((e) {
      if (event is AsyncEvent) {
        event._onListenerCalled((future) {
          futures.add(future);
        });
      }
    });

    fire(event);

    await Future.microtask(() {});

    await subscription.cancel();

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  /// Listen to events of a specific type
  Stream<T> on<T>() {
    return _bus.on<T>();
  }

  /// Destroy the event bus
  void destroy() {
    _bus.destroy();
  }
}

/// Base class for events that need to wait for async listeners
///
/// Events extending this class can be used with [Bus.fireAndWait]
/// to wait for all async listeners to complete.
///
/// Example:
/// ```dart
/// class UserLoadedEvent extends AsyncEvent {
///   final String userId;
///   UserLoadedEvent(this.userId);
/// }
///
/// // Listener registers async work
/// bus.on<UserLoadedEvent>().listen((event) {
///   event.registerListener(() async {
///     await loadUserData(event.userId);
///   });
/// });
///
/// // Fire and wait for all listeners
/// await bus.fireAndWait(UserLoadedEvent('123'));
/// ```
abstract class AsyncEvent {
  final List<Future<void>> _futures = [];

  void _onListenerCalled(void Function(Future<void>) callback) {
    for (final future in _futures) {
      callback(future);
    }
  }

  /// Register an async listener handler
  ///
  /// Call this method inside a listener to register async work
  /// that [Bus.fireAndWait] should wait for.
  void registerListener(Future<void> Function() handler) {
    _futures.add(handler());
  }

  /// Wait for all registered listeners to complete
  Future<void> waitAll() async {
    if (_futures.isEmpty) return;
    await Future.wait(_futures);
  }
}
