/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueNotifier, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDeviceKind, PointerEvent;
import 'package:flutter/widgets.dart';

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

class HoverPointerScope extends StatefulWidget {
  final Widget child;

  const HoverPointerScope({required this.child, super.key});

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_HoverPointer>()
            ?.notifier
            ?.value ??
        hasHoverPointer;
  }

  @override
  State<HoverPointerScope> createState() => _HoverPointerScopeState();
}

class _HoverPointerScopeState extends State<HoverPointerScope> {
  final _canHover = ValueNotifier(
    hasHoverPointer || WidgetsBinding.instance.mouseTracker.mouseIsConnected,
  );

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _canHover.dispose();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    _canHover.value = switch (event.kind) {
      PointerDeviceKind.mouse || PointerDeviceKind.trackpad => true,
      PointerDeviceKind.touch ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus => false,
      PointerDeviceKind.unknown => _canHover.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    return _HoverPointer(notifier: _canHover, child: widget.child);
  }
}

class _HoverPointer extends InheritedNotifier<ValueNotifier<bool>> {
  const _HoverPointer({required super.notifier, required super.child});
}

extension HoverPointerContext on BuildContext {
  bool get canHover => HoverPointerScope.of(this);
}
