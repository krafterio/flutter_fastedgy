/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'client.dart';

/// A request as it leaves the [Fetcher], for a test to answer.
class MockRequest {
  /// HTTP method, uppercase (`GET`, `POST`, …).
  final String method;

  /// Path the caller asked for, before the base URL is joined - what a test
  /// matches on (`/me`, `/acme/projects`).
  final String path;

  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> headers;

  /// Payload sent with the request, as the caller passed it.
  final Object? body;

  const MockRequest({
    required this.method,
    required this.path,
    this.queryParameters = const {},
    this.headers = const {},
    this.body,
  });

  @override
  String toString() => '$method $path';
}

/// What the [Fetcher] gets back for a [MockRequest].
class MockResponse {
  final int statusCode;

  /// JSON-encodable payload, or null for an empty body.
  final Object? body;

  /// A JSON answer - the shape every FastEdgy route returns.
  const MockResponse.json(this.body, {this.statusCode = 200});

  /// An answer with no body (a delete, a 204).
  const MockResponse.empty({this.statusCode = 204}) : body = null;

  /// A refusal the [Fetcher] maps to an `HttpError` of that status.
  const MockResponse.error(this.statusCode, {this.body});
}

typedef MockResponder = FutureOr<MockResponse> Function(MockRequest request);

/// Builds a [Fetcher] whose requests never leave the process: [respond] answers
/// each one.
///
/// Everything above the transport is the real thing - interceptors, JSON
/// decoding, error mapping - so a test drives the very [Fetcher] the app runs
/// on, and never has to reach for the HTTP client it wraps.
///
/// ```dart
/// final fetcher = createMockFetcher((request) {
///   if (request.path.endsWith('/me')) {
///     return const MockResponse.json({'id': 1, 'email': 'ada@example.com'});
///   }
///
///   return const MockResponse.error(404);
/// });
/// ```
///
/// Connection retry is off by default: a test that scripts a failure wants to
/// see it once, not three times.
Fetcher createMockFetcher(
  MockResponder respond, {
  String baseUrl = 'http://mock.test',
  List<dynamic>? customInterceptors,
  bool enableAuth = true,
  bool enableTimezone = true,
  bool enableRefreshToken = true,
  bool enableConnectionRetry = false,
  bool enableLogging = false,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl))
    ..httpClientAdapter = _MockAdapter(respond);

  return Fetcher.create(
    dio: dio,
    customInterceptors: customInterceptors,
    enableAuth: enableAuth,
    enableTimezone: enableTimezone,
    enableRefreshToken: enableRefreshToken,
    enableConnectionRetry: enableConnectionRetry,
    enableLogging: enableLogging,
  );
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.respond);

  final MockResponder respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final answer = await respond(
      MockRequest(
        method: options.method,
        path: options.path,
        queryParameters: {...options.queryParameters},
        headers: {...options.headers},
        body: options.data,
      ),
    );

    return ResponseBody.fromString(
      answer.body == null ? '' : jsonEncode(answer.body),
      answer.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
