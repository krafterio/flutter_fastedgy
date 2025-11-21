/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart' as dio;

// Export Dio's interceptor-related classes for external use
export 'package:dio/dio.dart' show Interceptor, RequestOptions, RequestInterceptorHandler;

/// Alias for Dio's Interceptor
typedef ApiInterceptor = dio.Interceptor;

/// Configuration for an interceptor with priority
///
/// Priority determines the order of execution:
/// - Higher priority = executed first
/// - Default priority = 100
///
/// Suggested priorities:
/// - 100+: Request transformation (e.g., URL rewriting)
/// - 50-99: Authentication, security
/// - 20-49: Logging, monitoring
/// - 0-19: Error handling
class InterceptorConfig {
  /// The interceptor instance
  final ApiInterceptor interceptor;

  /// Execution priority (higher = first)
  final int priority;

  const InterceptorConfig(
    this.interceptor, {
    this.priority = 100,
  });

  /// Create from an Interceptor with default priority
  factory InterceptorConfig.fromInterceptor(ApiInterceptor interceptor) {
    return InterceptorConfig(interceptor);
  }
}
