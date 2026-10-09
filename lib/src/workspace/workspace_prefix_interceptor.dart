/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:dio/dio.dart';

import '../container/container.dart';
import '../logging/logger.dart';
import 'workspace_provider.dart';

/// The workspaces augmenting the [Fetcher], which knows nothing of them: a
/// request under `/{workspace}` waits for the choice of the current workspace
/// ([WorkspaceProvider.ensureCurrent]) and goes under its slug; without one,
/// under [WorkspaceProvider.workspaceless], or it is refused when that is
/// `null`. A request under the current workspace answering 404 has the list
/// read again ([WorkspaceProvider.isWorkspaceError]): the workspace may be
/// gone. The same as vue-fastedgy's `useWorkspaces`.
///
/// The provider is the one registered as [WorkspaceProvider], looked up on
/// each request: it is registered after the fetcher it serves.
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

    unawaited(_route(options, handler));
  }

  Future<void> _route(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final workspaces = _workspaces;
    final slug = await workspaces?.ensureCurrent();
    final target = slug ?? workspaces?.workspaceless;

    // A path that keeps the placeholder would reach a route that does not
    // exist, and its 404 would hide the real fault: no workspace to read.
    if (target == null || target.isEmpty) {
      _log.warning(
        'Dropped a request with no workspace to go under: ${options.path}',
      );
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'No workspace to send ${options.path} under',
        ),
      );

      return;
    }

    options.path = options.path.replaceAll(_placeholder, '/$target');

    if (slug != null) {
      options.extra[_tenantKey] = slug;
    }

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
