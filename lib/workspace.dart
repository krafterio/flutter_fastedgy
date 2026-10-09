/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// The account's workspaces and the `/{workspace}` tenant of the requests,
/// for an application serving one workspace at a time.
///
/// Kept out of the main barrel: it is opt-in, and an application that wrote
/// its own `WorkspaceProvider` keeps compiling.
library;

export 'src/workspace/workspace_prefix_interceptor.dart';
export 'src/workspace/workspace_provider.dart';
