/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import '../timezone_provider.dart';

/// Interceptor that automatically adds the X-Timezone header to requests
///
/// Injects the device timezone from TimezoneProvider into every request.
/// The timezone is sent as an IANA timezone identifier (e.g., 'Europe/Paris').
///
/// Example:
/// ```dart
/// final timezoneProvider = TimezoneProvider();
/// await timezoneProvider.initialize();
///
/// final fetcher = Fetcher.create(
///   customInterceptors: [
///     InterceptorConfig(
///       TimezoneInterceptor(timezoneProvider),
///       priority: 45,
///     ),
///   ],
/// );
/// ```
class TimezoneInterceptor extends Interceptor {
  final TimezoneProvider _timezoneProvider;

  TimezoneInterceptor(this._timezoneProvider);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Get the device timezone
    final timezone = _timezoneProvider.getTimezone();

    // Add X-Timezone header
    options.headers['X-Timezone'] = timezone;

    handler.next(options);
  }
}
