/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../bus/events.dart';

/// Event fired when a user logs in
class AuthLoggedEvent extends Event {
  const AuthLoggedEvent();
}

/// Event fired when a user logs out
class AuthLogoutEvent extends Event {
  const AuthLogoutEvent();
}
