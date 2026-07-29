/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _custom = FastEdgyThemeData(
  colors: ColorRoles.fallback,
  radius: 17.0,
  spacing: 9.0,
);

void main() {
  group('FastEdgyTheme', () {
    testWidgets('falls back where no application has spoken', (tester) async {
      late FastEdgyThemeData seen;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = FastEdgyTheme.of(context);

            return const SizedBox();
          },
        ),
      );

      expect(seen, FastEdgyThemeData.fallback);
    });

    testWidgets('maybeOf tells a mounted theme from a fallback', (
      tester,
    ) async {
      late FastEdgyThemeData? bare;
      late FastEdgyThemeData? themed;

      await tester.pumpWidget(
        Column(
          children: [
            Builder(
              builder: (context) {
                bare = FastEdgyTheme.maybeOf(context);

                return const SizedBox();
              },
            ),
            FastEdgyTheme(
              data: _custom,
              child: Builder(
                builder: (context) {
                  themed = FastEdgyTheme.maybeOf(context);

                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      );

      expect(bare, isNull);
      expect(themed, _custom);
    });

    testWidgets('rebuilds its dependents only when the data changes', (
      tester,
    ) async {
      var builds = 0;

      // One instance, reused: Flutter skips an identical child widget, so a
      // rebuild can only come from the inherited dependency.
      final child = Builder(
        builder: (context) {
          FastEdgyTheme.of(context);
          builds++;

          return const SizedBox();
        },
      );

      Widget tree(FastEdgyThemeData data) =>
          FastEdgyTheme(data: data, child: child);

      await tester.pumpWidget(tree(_custom));
      expect(builds, 1);

      await tester.pumpWidget(tree(_custom.copyWith()));
      expect(builds, 1, reason: 'an equal theme is not a change');

      await tester.pumpWidget(tree(_custom.copyWith(radius: 2.0)));
      expect(builds, 2);
    });

    testWidgets('survives into an overlay entry when captured', (tester) async {
      late BuildContext anchor;
      late OverlayState overlay;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) {
                  overlay = Overlay.of(context);

                  return FastEdgyTheme(
                    data: _custom,
                    child: Builder(
                      builder: (context) {
                        anchor = context;

                        return const SizedBox();
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

      final captured = InheritedTheme.capture(
        from: anchor,
        to: overlay.context,
      );

      FastEdgyThemeData? floating;
      FastEdgyThemeData? uncaptured;

      overlay.insert(
        OverlayEntry(
          builder: (context) => captured.wrap(
            Builder(
              builder: (context) {
                floating = FastEdgyTheme.of(context);

                return const SizedBox();
              },
            ),
          ),
        ),
      );
      overlay.insert(
        OverlayEntry(
          builder: (context) {
            uncaptured = FastEdgyTheme.of(context);

            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      expect(floating, _custom);
      expect(
        uncaptured,
        FastEdgyThemeData.fallback,
        reason: 'an overlay is a separate subtree — this is what capture fixes',
      );
    });
  });

  group('FastEdgyThemeData', () {
    test('lerp interpolates the continuous roles', () {
      const a = FastEdgyThemeData(radius: 0.0, spacing: 0.0);
      const b = FastEdgyThemeData(radius: 10.0, spacing: 20.0);

      final mid = FastEdgyThemeData.lerp(a, b, 0.5);

      expect(mid.radius, 5.0);
      expect(mid.spacing, 10.0);
    });

    test('lerp keeps density discrete', () {
      const a = FastEdgyThemeData(density: Density.compact);
      const b = FastEdgyThemeData(density: Density.comfortable);

      expect(FastEdgyThemeData.lerp(a, b, 0.25).density, Density.compact);
      expect(FastEdgyThemeData.lerp(a, b, 0.75).density, Density.comfortable);
    });

    test('copyWith touches one role and leaves the rest', () {
      final wider = FastEdgyThemeData.fallback.copyWith(radius: 12.0);

      expect(wider.radius, 12.0);
      expect(wider.colors, FastEdgyThemeData.fallback.colors);
      expect(wider.typography, FastEdgyThemeData.fallback.typography);
    });
  });
}
