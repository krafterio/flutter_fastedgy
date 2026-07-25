/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Error classification used by the offline layer to tell a request the server
/// refused from one it never answered.
///
/// It lives with the error types it inspects ([HttpError] and friends) so the
/// lower layers - the logger among them - can classify a failure without
/// depending on the offline layer.
library;

export '../fetcher/http_error.dart'
    show
        describeUnavailable,
        errorStatusCode,
        isOfflineError,
        isRetryableServerError,
        isServerUnavailable;
