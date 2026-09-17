/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'theme/breakpoints.dart';
import 'theme/theme.dart';

class BreakpointScope extends StatelessWidget {
  final Widget child;

  const BreakpointScope({required this.child, super.key});

  static Breakpoint of(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<_BreakpointScope>();

    return scoped?.breakpoint ??
        FastEdgyTheme.of(context).breakpoints
            .fromWidth(MediaQuery.sizeOf(context).width);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        return _BreakpointScope(
          breakpoint: FastEdgyTheme.of(context).breakpoints.fromWidth(width),
          child: child,
        );
      },
    );
  }
}

class _BreakpointScope extends InheritedWidget {
  final Breakpoint breakpoint;

  const _BreakpointScope({required this.breakpoint, required super.child});

  @override
  bool updateShouldNotify(_BreakpointScope oldWidget) {
    return oldWidget.breakpoint != breakpoint;
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, Breakpoint breakpoint) builder;

  const ResponsiveBuilder({required this.builder, super.key});

  @override
  Widget build(BuildContext context) => builder(context, context.breakpoint);
}

extension BreakpointContext on BuildContext {
  Breakpoint get breakpoint => BreakpointScope.of(this);

  Breakpoints get breakpoints => FastEdgyTheme.of(this).breakpoints;
}
