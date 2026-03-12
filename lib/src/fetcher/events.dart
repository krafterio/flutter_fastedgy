/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../bus/events.dart';

/// Base class for all fetch events
abstract class FetchEvent extends Event {
  /// The URL being fetched
  final String url;

  const FetchEvent(this.url);
}

/// Event fired before a request is sent
///
/// Listeners can modify the request options before it's sent
class FetchRequestEvent extends FetchEvent {
  /// Request options (can be modified by listeners)
  final Map<String, dynamic> options;

  const FetchRequestEvent(super.url, this.options);
}

/// Event fired when a request succeeds
class FetchSuccessEvent extends FetchEvent {
  /// Response status code
  final int statusCode;

  /// Response data (parsed JSON or raw data)
  final dynamic data;

  /// Response headers
  final Map<String, List<String>> headers;

  const FetchSuccessEvent(super.url, this.statusCode, this.data, this.headers);
}

/// Event fired when a request fails
class FetchErrorEvent extends FetchEvent {
  /// The error that occurred
  final Object error;

  /// Stack trace if available
  final StackTrace? stackTrace;

  const FetchErrorEvent(super.url, this.error, [this.stackTrace]);
}
