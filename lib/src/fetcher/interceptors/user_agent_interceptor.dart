/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../../app_info/user_agent.dart';

/// Interceptor that adds the [UserAgent] header to all Dio requests.
///
/// The User-Agent itself is the standalone [UserAgent] service — share it for
/// non-Dio transports (e.g. a WebSocket handshake) by reading `userAgent.value`.
class UserAgentInterceptor extends Interceptor {
  final UserAgent userAgent;

  UserAgentInterceptor(this.userAgent);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['User-Agent'] = userAgent.value;
    handler.next(options);
  }
}
