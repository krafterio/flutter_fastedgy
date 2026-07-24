/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Cross-process guard around the outbox replay.
///
/// App instances sharing one offline database also share its outbox: two of
/// them replaying at the same time would send the same operations twice. The
/// [SyncEngine] takes this lock before draining the queue and releases it right
/// after; an instance that cannot take it defers instead of replaying.
///
/// Implementations must be backed by something the operating system releases
/// when a process dies — a file lock — and never by in-memory state, which a
/// crashed instance would leave held forever.
abstract class SyncLock {
  /// Takes the replay slot, or returns `false` when another process holds it.
  Future<bool> tryAcquire();

  /// Releases the slot taken by [tryAcquire].
  Future<void> release();
}
