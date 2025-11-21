/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import 'events.dart';
import 'http_error.dart';

/// Lightweight wrapper over Dio with event bus integration
///
/// Provides a clean API for HTTP requests with automatic JSON handling,
/// request cancellation, and event bus hooks for middleware.
class Fetcher {
  final Dio _dio;
  final Bus _bus;
  final Map<String, CancelToken> _cancelTokens = {};
  final CancelToken _globalCancelToken = CancelToken();

  Fetcher._({
    Dio? dio,
    Bus? bus,
  })  : _dio = dio ?? Dio(),
        _bus = bus ?? getService<Bus>();

  /// Create a new Fetcher instance
  ///
  /// Internal constructor. Use [useFetcher] or [useFetcherService] instead.
  factory Fetcher.create({Dio? dio, Bus? bus}) {
    return Fetcher._(dio: dio, bus: bus);
  }

  /// Perform a GET request
  ///
  /// Example:
  /// ```dart
  /// final response = await fetcher.get('/users', params: {'page': 1});
  /// final users = response.data;
  /// ```
  Future<Response> get(
    String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
    ResponseType? responseType,
  }) async {
    return _request(
      path,
      method: 'GET',
      queryParameters: params,
      headers: headers,
      id: id,
      responseType: responseType,
    );
  }

  /// Perform a POST request
  ///
  /// Example:
  /// ```dart
  /// final response = await fetcher.post('/users', {
  ///   'name': 'John Doe',
  ///   'email': 'john@example.com',
  /// });
  /// ```
  Future<Response> post(
    String path,
    dynamic data, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
  }) async {
    return _request(
      path,
      method: 'POST',
      data: data,
      queryParameters: params,
      headers: headers,
      id: id,
    );
  }

  /// Perform a PUT request
  Future<Response> put(
    String path,
    dynamic data, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
  }) async {
    return _request(
      path,
      method: 'PUT',
      data: data,
      queryParameters: params,
      headers: headers,
      id: id,
    );
  }

  /// Perform a PATCH request
  Future<Response> patch(
    String path,
    dynamic data, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
  }) async {
    return _request(
      path,
      method: 'PATCH',
      data: data,
      queryParameters: params,
      headers: headers,
      id: id,
    );
  }

  /// Perform a DELETE request
  Future<Response> delete(
    String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
  }) async {
    return _request(
      path,
      method: 'DELETE',
      queryParameters: params,
      headers: headers,
      id: id,
    );
  }

  /// Internal request method
  Future<Response> _request(
    String path, {
    required String method,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    String? id,
    ResponseType? responseType,
  }) async {
    // Create cancel token for this request
    final cancelToken = CancelToken();
    if (id != null) {
      _cancelTokens[id] = cancelToken;
    }

    // Build options
    final options = <String, dynamic>{
      'method': method,
      'headers': headers ?? {},
      'queryParameters': queryParameters ?? {},
      'responseType': responseType ?? ResponseType.json,
    };

    // Fire request event (allows listeners to modify options)
    _bus.fire(FetchRequestEvent(path, options));

    try {
      // Execute request
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: options['queryParameters'] as Map<String, dynamic>?,
        options: Options(
          method: method,
          headers: options['headers'] as Map<String, dynamic>?,
          responseType: options['responseType'] as ResponseType?,
        ),
        cancelToken: cancelToken,
      );

      // Fire success event
      _bus.fire(FetchSuccessEvent(
        path,
        response.statusCode ?? 200,
        response.data,
        response.headers.map,
      ));

      // Clean up cancel token
      if (id != null) {
        _cancelTokens.remove(id);
      }

      return response;
    } on DioException catch (e) {
      final httpError = HttpError.fromDioException(e);

      // Fire error event
      _bus.fire(FetchErrorEvent(path, httpError, e.stackTrace));

      // Clean up cancel token
      if (id != null) {
        _cancelTokens.remove(id);
      }

      throw httpError;
    } catch (e, stackTrace) {
      // Fire error event for non-Dio errors
      _bus.fire(FetchErrorEvent(path, e, stackTrace));

      // Clean up cancel token
      if (id != null) {
        _cancelTokens.remove(id);
      }

      rethrow;
    }
  }

  /// Cancel all pending requests or a specific request by ID
  ///
  /// Examples:
  /// ```dart
  /// // Cancel all requests
  /// fetcher.abort();
  ///
  /// // Cancel specific request
  /// fetcher.abort('search-users');
  /// ```
  void abort([String? id]) {
    if (id != null) {
      // Cancel specific request
      final token = _cancelTokens[id];
      if (token != null && !token.isCancelled) {
        token.cancel('Request cancelled: $id');
        _cancelTokens.remove(id);
      }
    } else {
      // Cancel all requests
      for (final token in _cancelTokens.values) {
        if (!token.isCancelled) {
          token.cancel('All requests cancelled');
        }
      }
      _cancelTokens.clear();

      if (!_globalCancelToken.isCancelled) {
        _globalCancelToken.cancel('All requests cancelled');
      }
    }
  }

  /// Dispose and clean up resources
  void dispose() {
    abort(); // Cancel all pending requests
  }
}
