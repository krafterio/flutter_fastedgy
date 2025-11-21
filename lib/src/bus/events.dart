/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Base class for all events
///
/// All custom events should extend this class.
///
/// Example:
/// ```dart
/// class MyCustomEvent extends Event {
///   final String data;
///   const MyCustomEvent(this.data);
/// }
/// ```
abstract class Event {
  const Event();
}
