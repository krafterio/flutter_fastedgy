/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../bus/events.dart';

/// What is held may have moved without anyone saying so: read it again.
///
/// Fired by the realtime socket on a handshake that follows an earlier one, and
/// by an application whose screens outlive a change of what they show, a
/// workspace switch for one.
class ResourcesStaleEvent extends Event {
  const ResourcesStaleEvent();
}

/// Something the server announced under a name of its own, rather than a write
/// on a model: `import.finished`.
class RealtimeEvent extends Event {
  const RealtimeEvent(this.type, this.data, {this.truncated = false});

  final String type;
  final Object? data;
  final bool truncated;
}
