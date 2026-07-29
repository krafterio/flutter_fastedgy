/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _light = FastEdgyThemeData(colors: ColorRoles.fallback, radius: 0.0);

final _dark = FastEdgyThemeData(
  colors: ColorRoles.fallback.copyWith(
    ink: const Color(0xFFFFFFFF),
    surface: const Color(0xFF000000),
  ),
  radius: 20.0,
);

void main() {
  group('AnimatedTheme', () {
    testWidgets('interpolates instead of jumping', (tester) async {
      late FastEdgyThemeData seen;

      Widget tree(FastEdgyThemeData data) => AnimatedTheme(
        data: data,
        duration: const Duration(milliseconds: 200),
        child: Builder(
          builder: (context) {
            seen = FastEdgyTheme.of(context);

            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(tree(_light));
      expect(seen, _light);

      await tester.pumpWidget(tree(_dark));
      await tester.pump(const Duration(milliseconds: 100));

      expect(seen.radius, greaterThan(0.0));
      expect(seen.radius, lessThan(20.0));
      expect(
        seen.colors.surface,
        isNot(_light.colors.surface),
        reason: 'the colours travel with the rest',
      );

      await tester.pumpAndSettle();
      expect(seen, _dark);
    });

    test('ThemeDataTween lerps end to end', () {
      final tween = ThemeDataTween(begin: _light, end: _dark);

      expect(tween.lerp(0.0), _light);
      expect(tween.lerp(1.0), _dark);
      expect(tween.lerp(0.5).radius, 10.0);
    });
  });
}
