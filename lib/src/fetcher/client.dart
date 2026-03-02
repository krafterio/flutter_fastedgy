/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import '../auth/token_storage.dart';
import '../auth/auth_provider.dart';
import 'events.dart';
import 'http_error.dart';
import 'interceptor_config.dart';
import 'interceptors/interceptors.dart';
import 'timezone_provider.dart';

/// Lightweight wrapper over Dio with event bus integration
///
/// Provides a clean API for HTTP requests with automatic JSON handling,
/// request cancellation, and event bus hooks for middleware.
class Fetcher {
  final Dio _dio;
  final Bus _bus;
  final Map<String, CancelToken> _cancelTokens = {};
  final CancelToken _globalCancelToken = CancelToken();

  Fetcher._({Dio? dio, Bus? bus})
    : _dio = dio ?? Dio(),
      _bus = bus ?? getService<Bus>();

  /// Create a new Fetcher instance with configurable interceptors
  ///
  /// Automatically configures:
  /// - Base URL from environment
  /// - Default interceptors with priorities (Auth, RefreshToken, Logging, Error)
  ///
  /// You can add custom interceptors with [customInterceptors].
  /// Accepts [InterceptorConfig] (with priority) or [Interceptor] (default priority).
  /// Interceptors are sorted by priority (highest first).
  ///
  /// Default priorities:
  /// - Auth: 50
  /// - Timezone: 45
  /// - RefreshToken: 40
  /// - Logging: 30
  /// - Error: 10
  ///
  /// Example:
  /// ```dart
  /// Fetcher.create(
  ///   customInterceptors: [
  ///     InterceptorConfig(AppPrefixInterceptor(), priority: 100),
  ///     MyCustomInterceptor(), // priority = 0 (default)
  ///   ],
  /// );
  /// ```
  factory Fetcher.create({
    Dio? dio,
    Bus? bus,
    List<dynamic>? customInterceptors,
    bool enableAuth = true,
    bool enableTimezone = true,
    bool enableRefreshToken = true,
    bool enableLogging = true,
    bool enableErrorTransform = true,
    bool logHeaders = false,
    bool logBody = true,
  }) {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';

    final dioInstance =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        );

    // Build list of interceptors with priorities
    final allInterceptors = <InterceptorConfig>[];

    // Create shared RefreshTokenLock if both auth and refresh token are enabled
    RefreshTokenLock? refreshTokenLock;
    if (enableRefreshToken && hasService<AuthProvider>()) {
      refreshTokenLock = RefreshTokenLock(getService<AuthProvider>());
    }

    // Add default interceptors
    if (enableAuth && hasService<TokenStorage>()) {
      allInterceptors.add(
        InterceptorConfig(
          AuthInterceptor(getService<TokenStorage>(), refreshTokenLock),
          priority: 50,
        ),
      );
    }

    if (enableTimezone && hasService<TimezoneProvider>()) {
      allInterceptors.add(
        InterceptorConfig(
          TimezoneInterceptor(getService<TimezoneProvider>()),
          priority: 45,
        ),
      );
    }

    if (enableRefreshToken &&
        refreshTokenLock != null &&
        hasService<TokenStorage>()) {
      allInterceptors.add(
        InterceptorConfig(
          RefreshTokenInterceptor(
            refreshTokenLock,
            dioInstance,
            getService<TokenStorage>(),
          ),
          priority: 40,
        ),
      );
    }

    if (enableLogging) {
      allInterceptors.add(
        InterceptorConfig(
          LoggingInterceptor(logHeaders: logHeaders, logBody: logBody),
          priority: 30,
        ),
      );
    }

    if (enableErrorTransform) {
      allInterceptors.add(InterceptorConfig(ErrorInterceptor(), priority: 10));
    }

    // Add custom interceptors
    if (customInterceptors != null) {
      for (final item in customInterceptors) {
        if (item is InterceptorConfig) {
          allInterceptors.add(item);
        } else if (item is Interceptor) {
          allInterceptors.add(InterceptorConfig(item));
        }
      }
    }

    // Sort by priority (highest first)
    allInterceptors.sort((a, b) => b.priority.compareTo(a.priority));

    // Add interceptors to Dio
    for (final config in allInterceptors) {
      dioInstance.interceptors.add(config.interceptor);
    }

    return Fetcher._(dio: dioInstance, bus: bus);
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
  /// // Simple POST
  /// final response = await fetcher.post('/users', {
  ///   'name': 'John Doe',
  ///   'email': 'john@example.com',
  /// });
  ///
  /// // POST with progress tracking
  /// final response = await fetcher.post(
  ///   '/upload',
  ///   formData,
  ///   onSendProgress: (sent, total) {
  ///     print('Progress: ${(sent / total * 100).toStringAsFixed(0)}%');
  ///   },
  /// );
  /// ```
  Future<Response> post(
    String path,
    dynamic data, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    String? id,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    // If onSendProgress is provided, use direct Dio call to access it
    if (onSendProgress != null) {
      return _requestWithProgress(
        path,
        method: 'POST',
        data: data,
        queryParameters: params,
        headers: headers,
        id: id,
        onSendProgress: onSendProgress,
      );
    }

    // Otherwise, use standard request method
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

  /// Sanitize header values for HTTP compliance.
  ///
  /// HTTP headers must be ASCII-only. Any value containing non-ASCII
  /// characters (accents, emojis, etc.) is URI-encoded to ensure
  /// safe transmission through proxies and servers.
  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    return headers.map((key, value) {
      if (value is String && value.codeUnits.any((unit) => unit > 127)) {
        return MapEntry(key, Uri.encodeComponent(value));
      }
      return MapEntry(key, value);
    });
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
      'headers': _sanitizeHeaders(headers ?? {}),
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
      _bus.fire(
        FetchSuccessEvent(
          path,
          response.statusCode ?? 200,
          response.data,
          response.headers.map,
        ),
      );

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

  /// Internal request method with progress tracking
  Future<Response> _requestWithProgress(
    String path, {
    required String method,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    String? id,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    // Create cancel token for this request
    final cancelToken = CancelToken();
    if (id != null) {
      _cancelTokens[id] = cancelToken;
    }

    // Build options
    final options = <String, dynamic>{
      'method': method,
      'headers': _sanitizeHeaders(headers ?? {}),
      'queryParameters': queryParameters ?? {},
    };

    // Fire request event
    _bus.fire(FetchRequestEvent(path, options));

    try {
      final response = await _dio.request(
        path,
        data: data,
        queryParameters: options['queryParameters'] as Map<String, dynamic>?,
        options: Options(
          method: method,
          headers: options['headers'] as Map<String, dynamic>?,
        ),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );

      // Fire success event
      _bus.fire(
        FetchSuccessEvent(
          path,
          response.statusCode ?? 200,
          response.data,
          response.headers.map,
        ),
      );

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
