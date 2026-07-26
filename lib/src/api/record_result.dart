/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// A single record plus where it came from — the single-record counterpart of
/// [PaginationResult].
///
/// [ApiModel.get] returns the record alone, which leaves a caller unable to
/// tell a server answer from a mirror fallback; [ApiModel.getResult] keeps that
/// distinction so a UI can say it is showing local data.
class RecordResult<T> {
  final T value;

  /// Whether the record was served from the local mirror instead of the server.
  ///
  /// True when the server could not be reached and the offline engine fell back
  /// to the cache: the record is as fresh as the last successful read.
  final bool fromCache;

  const RecordResult(this.value, {this.fromCache = false});
}
