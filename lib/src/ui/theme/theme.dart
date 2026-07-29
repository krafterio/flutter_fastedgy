/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'theme_data.dart';

/// Carries a [FastEdgyThemeData] down the tree.
///
/// An [InheritedTheme] rather than a plain [InheritedWidget], and that is the
/// whole point: a popover, a mention list, a slash menu live in an
/// [OverlayEntry] — a different subtree, where an ordinary inherited widget is
/// simply not found. `InheritedTheme.capture(from:, to:).wrap(child)` re-applies
/// every captured theme inside the overlay, and only an [InheritedTheme]
/// participates in that.
///
/// Forgetting it produces a bug that is invisible in tests and obvious in the
/// product: everything is themed until something floats.
class FastEdgyTheme extends InheritedTheme {
  final FastEdgyThemeData data;

  const FastEdgyTheme({required this.data, required super.child, super.key});

  /// The theme in scope, or [FastEdgyThemeData.fallback] where none was mounted
  /// — a widget is never left without one.
  static FastEdgyThemeData of(BuildContext context) {
    return maybeOf(context) ?? FastEdgyThemeData.fallback;
  }

  /// The theme in scope, or null. For the rare caller that needs to know
  /// whether an application has actually spoken.
  static FastEdgyThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FastEdgyTheme>()?.data;
  }

  @override
  Widget wrap(BuildContext context, Widget child) {
    return FastEdgyTheme(data: data, child: child);
  }

  @override
  bool updateShouldNotify(FastEdgyTheme oldWidget) => data != oldWidget.data;
}
