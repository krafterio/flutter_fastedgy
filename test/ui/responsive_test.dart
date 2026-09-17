/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _material = Breakpoints(sm: 600, md: 840, lg: 1200, xl: 1600, xxl: 1920);

void main() {
  group('Breakpoints', () {
    test('map a width to the tailwind steps by default', () {
      const breakpoints = Breakpoints();

      expect(breakpoints.fromWidth(0), isA<BreakpointTN>());
      expect(breakpoints.fromWidth(639), isA<BreakpointTN>());
      expect(breakpoints.fromWidth(640), isA<BreakpointSM>());
      expect(breakpoints.fromWidth(767), isA<BreakpointSM>());
      expect(breakpoints.fromWidth(768), isA<BreakpointMD>());
      expect(breakpoints.fromWidth(1024), isA<BreakpointLG>());
      expect(breakpoints.fromWidth(1280), isA<BreakpointXL>());
      expect(breakpoints.fromWidth(1536), isA<BreakpointXXL>());
      expect(breakpoints.fromWidth(4000), isA<BreakpointXXL>());
    });

    test('map a width to the steps an application sets', () {
      expect(_material.fromWidth(599), isA<BreakpointTN>());
      expect(_material.fromWidth(600), isA<BreakpointSM>());
      expect(_material.fromWidth(839), isA<BreakpointSM>());
      expect(_material.fromWidth(840), isA<BreakpointMD>());
      expect(_material.fromWidth(1200), isA<BreakpointLG>());
      expect(_material.fromWidth(1600), isA<BreakpointXL>());
      expect(_material.fromWidth(1920), isA<BreakpointXXL>());
      expect(_material.copyWith(md: 900).fromWidth(840), isA<BreakpointSM>());
    });

    test('refuse steps out of order', () {
      expect(() => Breakpoints(sm: 900, md: 800), throwsAssertionError);
    });

    test('compare by value, and are equal by step and value', () {
      const breakpoints = Breakpoints();
      final breakpoint = breakpoints.fromWidth(800);

      expect(breakpoint >= breakpoints.sm, isTrue);
      expect(breakpoint >= breakpoints.md, isTrue);
      expect(breakpoint > breakpoints.md, isFalse);
      expect(breakpoint < breakpoints.lg, isTrue);
      expect(breakpoint <= breakpoints.tn, isFalse);
      expect(breakpoint, breakpoints.md);
      expect(breakpoint, isNot(breakpoints.sm));
      expect(const BreakpointSM(640), isNot(const BreakpointMD(640)));
      expect(
        _material,
        const Breakpoints(sm: 600, md: 840, lg: 1200, xl: 1600, xxl: 1920),
      );
      expect(_material, isNot(const Breakpoints()));
    });
  });

  group('FastEdgyThemeData', () {
    test('carries its breakpoints through copy, lerp and equality', () {
      const theme = FastEdgyThemeData();
      final custom = theme.copyWith(breakpoints: _material);

      expect(theme.breakpoints, const Breakpoints());
      expect(custom.breakpoints, _material);
      expect(custom.copyWith().breakpoints, _material);
      expect(custom, isNot(theme));
      expect(
        FastEdgyThemeData.lerp(theme, custom, 0.4).breakpoints,
        const Breakpoints(),
      );
      expect(FastEdgyThemeData.lerp(theme, custom, 0.6).breakpoints, _material);
    });
  });

  group('responsive context', () {
    Future<void> pump(
      WidgetTester tester,
      Size window,
      Widget child, {
      Breakpoints? breakpoints,
    }) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = window;
      addTearDown(tester.view.reset);

      final app = Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      );

      return tester.pumpWidget(
        breakpoints == null
            ? app
            : FastEdgyTheme(
                data: FastEdgyThemeData(breakpoints: breakpoints),
                child: app,
              ),
      );
    }

    Widget probe(void Function(BuildContext context) read) {
      return Builder(
        builder: (context) {
          read(context);

          return const SizedBox();
        },
      );
    }

    testWidgets('reads the window against the default steps', (tester) async {
      late Breakpoint seen;
      await pump(
        tester,
        const Size(700, 600),
        probe((context) => seen = context.breakpoint),
      );

      expect(seen, isA<BreakpointSM>());
    });

    testWidgets('reads the window against the steps of the theme', (
      tester,
    ) async {
      late Breakpoint seen;
      late Breakpoints steps;
      await pump(
        tester,
        const Size(700, 600),
        probe((context) {
          seen = context.breakpoint;
          steps = context.breakpoints;
        }),
        breakpoints: _material,
      );

      expect(steps, _material);
      expect(seen, isA<BreakpointSM>());
      expect(seen >= steps.md, isFalse);
    });

    testWidgets('a scope measures the room it is given', (tester) async {
      late Breakpoint window;
      late Breakpoint scoped;
      await pump(
        tester,
        const Size(1400, 800),
        Row(
          children: [
            probe((context) => window = context.breakpoint),
            SizedBox(
              width: 500,
              child: BreakpointScope(
                child: probe((context) => scoped = context.breakpoint),
              ),
            ),
          ],
        ),
      );

      expect(window, isA<BreakpointXL>());
      expect(scoped, isA<BreakpointTN>());
    });

    testWidgets('the builder follows the window', (tester) async {
      final seen = <Breakpoint>[];
      Widget builder() => ResponsiveBuilder(
        builder: (context, breakpoint) {
          seen.add(breakpoint);

          return const SizedBox();
        },
      );

      await pump(tester, const Size(500, 600), builder());
      await pump(tester, const Size(1300, 600), builder());

      expect(seen.first, isA<BreakpointTN>());
      expect(seen.last, isA<BreakpointXL>());
    });
  });

  group('DeviceType', () {
    testWidgets('a desktop platform is a desktop', (tester) async {
      expect(DeviceType.current, DeviceType.desktop);
      expect(isDesktop, isTrue);
      expect(isMobile, isFalse);
      expect(isWeb, isFalse);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a mobile platform is a mobile', (tester) async {
      expect(DeviceType.current, DeviceType.mobile);
      expect(isMobile, isTrue);
      expect(isDesktop, isFalse);
      expect(isWeb, isFalse);
    }, variant: TargetPlatformVariant.mobile());
  });
}
