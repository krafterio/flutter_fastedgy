/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../bus/bus.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
import 'api_model.dart';

/// Base class for manual API services consuming a resource directly.
///
/// Unlike [ApiModel] (automatic CRUD conventions over a collection), a
/// resource service writes its own methods against [fetcher] — any HTTP verb,
/// any payload shape, any number of routes under [basePath].
///
/// Example:
/// ```dart
/// class MeApi extends ApiResource {
///   MeApi() : super('/me');
///
///   Future<User> getMe() async =>
///       User((await fetcher.get(basePath)).data as Map<String, dynamic>);
/// }
/// ```
abstract class ApiResource {
  /// The base path of this resource (e.g., '/me')
  final String basePath;

  /// The HTTP client used for requests
  final Fetcher fetcher;

  /// Create a manual API service for a specific resource
  ///
  /// [basePath] is the base URL path of this resource (e.g., '/me')
  /// [fetcher] is optional; if not provided, uses the global Fetcher from DI
  ApiResource(this.basePath, {Fetcher? fetcher})
    : fetcher = fetcher ?? getService<Fetcher>();

  /// Notify listeners that this resource changed (fires a
  /// [ResourceChangedEvent] on the bus, like [ApiModel]).
  void notifyChanged([ResourceChangeType? type, Object? id]) =>
      getService<Bus>().fire(
        ResourceChangedEvent(basePath, type: type, id: id),
      );
}
