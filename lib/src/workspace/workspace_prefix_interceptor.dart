/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:dio/dio.dart';

import '../container/container.dart';
import '../logging/logger.dart';
import 'workspace_provider.dart';

/// Puts the current workspace's slug in place of `/{workspace}` in each
/// request path, as vue-fastedgy's fetcher does with `workspace: true`, and
/// reads the workspaces again when a tenant request says they changed
/// ([WorkspaceProvider.isWorkspaceError]).
///
/// A path that keeps the placeholder is never sent: it would reach a route
/// that does not exist and come back as a 404, hiding the real fault, a read
/// of the tenant before a workspace is chosen.
///
/// The provider is the one registered as [WorkspaceProvider], looked up on
/// each request: it is registered after the fetcher it serves. An application
/// subclassing it registers its instance under both types.
class WorkspacePrefixInterceptor extends Interceptor {
  static const _placeholder = '/{workspace}';

  /// Marks a tenant request, to recognize its errors.
  static const _tenantKey = 'fastedgy.workspace';

  final _log = getLogger('WorkspacePrefixInterceptor');

  WorkspaceProvider? get _workspaces =>
      hasService<WorkspaceProvider>() ? getService<WorkspaceProvider>() : null;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.contains(_placeholder)) {
      handler.next(options);

      return;
    }

    final slug = _workspaces?.currentSlug;

    if (slug == null || slug.isEmpty) {
      _log.warning(
        'Dropped a tenant-scoped request made before a workspace was selected: ${options.path}',
      );
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'No workspace selected for ${options.path}',
        ),
      );

      return;
    }

    options.path = options.path.replaceAll(_placeholder, '/$slug');
    options.extra[_tenantKey] = slug;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final workspaces = _workspaces;

    if (workspaces != null && err.requestOptions.extra[_tenantKey] != null) {
      final data = err.response?.data;
      final detail = data is Map ? data['detail'] : null;

      if (workspaces.isWorkspaceError(err.response?.statusCode, detail)) {
        unawaited(workspaces.refreshAfterError());
      }
    }

    handler.next(err);
  }
}
