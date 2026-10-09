/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:dio/dio.dart';

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
class WorkspacePrefixInterceptor extends Interceptor {
  /// [workspaces] is looked up on each request: the provider is registered
  /// after the fetcher it serves.
  WorkspacePrefixInterceptor(this._workspaces);

  static const _placeholder = '/{workspace}';

  /// Marks a tenant request, to recognize its errors.
  static const _tenantKey = 'fastedgy.workspace';

  final WorkspaceProvider? Function() _workspaces;
  final _log = getLogger('WorkspacePrefixInterceptor');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.contains(_placeholder)) {
      handler.next(options);

      return;
    }

    final slug = _workspaces()?.currentSlug;

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
    final workspaces = _workspaces();

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
