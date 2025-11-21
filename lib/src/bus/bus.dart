/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

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
/// ```
class Bus {
  final EventBus _bus = EventBus();

  /// Fire an event to all listeners
  void fire(dynamic event) {
    _bus.fire(event);
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
