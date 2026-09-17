/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
    // A browser sets the User-Agent itself and refuses the header.
    if (!kIsWeb) {
      options.headers['User-Agent'] = userAgent.value;
    }
    handler.next(options);
  }
}
