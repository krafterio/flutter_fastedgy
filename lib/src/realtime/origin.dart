/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:math';

import 'package:dio/dio.dart';

/// The header naming the client instance behind a request.
const originHeader = 'X-Origin-Id';

/// This running instance of the application, drawn once per process and never
/// stored: a relaunched application holds new holders, which owe a full read.
final String originId = _drawOriginId();

int _sequence = 0;

/// An origin of its own for one request, `<originId>.<n>`: a write the api
/// layer announces carries one, so that the echo of this request alone is
/// dropped.
String requestOrigin() => '$originId.${++_sequence}';

String _drawOriginId() {
  final random = Random.secure();

  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Stamps [originId] on every request that names no origin of its own.
class OriginInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent(originHeader, () => originId);
    handler.next(options);
  }
}
