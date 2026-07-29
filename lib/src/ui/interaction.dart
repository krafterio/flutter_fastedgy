/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// Whether what aims at this screen can hover.
///
/// The one question behind most of what a component draws differently here and
/// there: an affordance may wait to be hovered only where something is able to
/// hover it. A finger arrives already committed, so anything hidden until then
/// is simply not there — a handle that never shows, a gutter nobody can reach.
///
/// Asked of the platform rather than of the pointer at hand: a widget has to
/// decide what to build before any pointer has touched it.
bool get hasHoverPointer => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};
