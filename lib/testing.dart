/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Test seam for apps built on flutter_fastedgy.
///
/// Kept out of the main barrel so nothing but a test can reach it, and so an
/// app never has to depend on the HTTP client the [Fetcher] wraps.
library;

export 'src/fetcher/mock_transport.dart';
