/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../../container/container.dart';
import '../../sync/sync_status.dart';
import '../http_error.dart';

/// Reports every request's outcome to [SyncStatus], so whether the server
/// answers is known from the requests themselves.
///
/// The connectivity stream cannot answer that: a device on wifi whose server is
/// stopped, restarting or behind a dead upstream stays `online` while nothing
/// gets through. Anything gating on reachability — an action that would be lost,
/// a screen that needs the server — would read the wrong verdict.
///
/// Any answer proves the server is there, a refusal included: a 404 is the
/// server working. Only an unanswered request ([isServerUnavailable]) says it is
/// not.
///
/// Note: HttpError transformation is done in the Fetcher catch blocks, not here,
/// to maintain clean error propagation.
class ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _report(true);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _report(!isServerUnavailable(err));
    handler.next(err);
  }

  void _report(bool answering) {
    if (hasService<SyncStatus>()) {
      getService<SyncStatus>().setServerAnswering(answering);
    }
  }
}
