/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Stops dio from logging a warning, with a stack trace, on every request that
/// is not a CORS "simple request".
///
/// An authenticated API call never is one: the Authorization header alone is
/// off the CORS safelist, so the preflight is a given and the warning repeats
/// it request after request. The enriched connection error dio raises when a
/// preflight actually fails is emitted either way.
void silenceCorsWarning(Dio dio) {
  final adapter = dio.httpClientAdapter;

  if (adapter is BrowserHttpClientAdapter) {
    adapter.enableCORSWarning = false;
  }
}
