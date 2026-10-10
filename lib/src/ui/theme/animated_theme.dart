/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'theme.dart';
import 'theme_data.dart';

class FastEdgyThemeDataTween extends Tween<FastEdgyThemeData> {
  FastEdgyThemeDataTween({super.begin, super.end});

  @override
  FastEdgyThemeData lerp(double t) => FastEdgyThemeData.lerp(begin!, end!, t);
}

/// A [FastEdgyTheme] that interpolates when its data changes — light to dark
/// without the jump.
///
/// Optional in every sense: an application that wants an instant switch mounts
/// [FastEdgyTheme] directly and pays nothing for this.
class FastEdgyAnimatedTheme extends ImplicitlyAnimatedWidget {
  final FastEdgyThemeData data;
  final Widget child;

  const FastEdgyAnimatedTheme({
    required this.data,
    required this.child,
    super.key,
    super.curve,
    super.duration = const Duration(milliseconds: 200),
    super.onEnd,
  });

  @override
  AnimatedWidgetBaseState<FastEdgyAnimatedTheme> createState() =>
      _AnimatedThemeState();
}

class _AnimatedThemeState
    extends AnimatedWidgetBaseState<FastEdgyAnimatedTheme> {
  FastEdgyThemeDataTween? _data;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _data = visitor(
      _data,
      widget.data,
      (value) => FastEdgyThemeDataTween(begin: value as FastEdgyThemeData),
    ) as FastEdgyThemeDataTween?;
  }

  @override
  Widget build(BuildContext context) {
    return FastEdgyTheme(data: _data!.evaluate(animation), child: widget.child);
  }
}
