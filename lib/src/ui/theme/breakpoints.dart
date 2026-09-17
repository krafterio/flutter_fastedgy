/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

sealed class Breakpoint {
  final double value;

  const Breakpoint(this.value);

  bool operator <(Breakpoint other) => value < other.value;

  bool operator <=(Breakpoint other) => value <= other.value;

  bool operator >(Breakpoint other) => value > other.value;

  bool operator >=(Breakpoint other) => value >= other.value;

  @override
  bool operator ==(Object other) {
    return other is Breakpoint &&
        other.runtimeType == runtimeType &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

final class BreakpointTN extends Breakpoint {
  const BreakpointTN(super.value);
}

final class BreakpointSM extends Breakpoint {
  const BreakpointSM(super.value);
}

final class BreakpointMD extends Breakpoint {
  const BreakpointMD(super.value);
}

final class BreakpointLG extends Breakpoint {
  const BreakpointLG(super.value);
}

final class BreakpointXL extends Breakpoint {
  const BreakpointXL(super.value);
}

final class BreakpointXXL extends Breakpoint {
  const BreakpointXXL(super.value);
}

@immutable
class Breakpoints {
  final double _tn;
  final double _sm;
  final double _md;
  final double _lg;
  final double _xl;
  final double _xxl;

  const Breakpoints({
    double tn = 0,
    double sm = 640,
    double md = 768,
    double lg = 1024,
    double xl = 1280,
    double xxl = 1536,
  }) : assert(
         tn <= sm && sm <= md && md <= lg && lg <= xl && xl <= xxl,
         'Breakpoints must be given in ascending order',
       ),
       _tn = tn,
       _sm = sm,
       _md = md,
       _lg = lg,
       _xl = xl,
       _xxl = xxl;

  BreakpointTN get tn => BreakpointTN(_tn);

  BreakpointSM get sm => BreakpointSM(_sm);

  BreakpointMD get md => BreakpointMD(_md);

  BreakpointLG get lg => BreakpointLG(_lg);

  BreakpointXL get xl => BreakpointXL(_xl);

  BreakpointXXL get xxl => BreakpointXXL(_xxl);

  Breakpoint fromWidth(double width) {
    if (width < _sm) {
      return tn;
    }

    if (width < _md) {
      return sm;
    }

    if (width < _lg) {
      return md;
    }

    if (width < _xl) {
      return lg;
    }

    if (width < _xxl) {
      return xl;
    }

    return xxl;
  }

  Breakpoints copyWith({
    double? tn,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return Breakpoints(
      tn: tn ?? _tn,
      sm: sm ?? _sm,
      md: md ?? _md,
      lg: lg ?? _lg,
      xl: xl ?? _xl,
      xxl: xxl ?? _xxl,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is Breakpoints &&
        other._tn == _tn &&
        other._sm == _sm &&
        other._md == _md &&
        other._lg == _lg &&
        other._xl == _xl &&
        other._xxl == _xxl;
  }

  @override
  int get hashCode => Object.hash(_tn, _sm, _md, _lg, _xl, _xxl);
}
