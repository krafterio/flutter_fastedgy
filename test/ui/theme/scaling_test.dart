/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _authored = FastEdgyThemeData(radius: 8.0, spacing: 4.0);

/// A component drawn from the tokens alone — the only thing a scale is allowed
/// to change about it is its size.
class _Chip extends StatelessWidget {
  const _Chip();

  @override
  Widget build(BuildContext context) {
    final theme = FastEdgyTheme.of(context);

    return Padding(
      padding: EdgeInsets.all(theme.spacing * 2),
      child: SizedBox(width: theme.spacing * 10, height: theme.spacing * 4),
    );
  }
}

void main() {
  group('AdaptiveScaling', () {
    test('scales the sizes and leaves the colours alone', () {
      final scaled = AdaptiveScaling.mobile.scale(_authored);

      expect(scaled.radius, closeTo(10.0, 1e-9));
      expect(scaled.spacing, closeTo(5.0, 1e-9));
      expect(scaled.typography.body.fontSize, closeTo(17.5, 1e-9));
      expect(scaled.colors, _authored.colors);
      expect(scaled.scaling, AdaptiveScaling.mobile);
    });

    test('applying the same scale twice changes nothing', () {
      final once = AdaptiveScaling.mobile.scale(_authored);
      final twice = AdaptiveScaling.mobile.scale(once);

      expect(twice, once);
    });

    test('going back to desktop returns the theme that was authored', () {
      final round = AdaptiveScaling.desktop.scale(
        AdaptiveScaling.mobile.scale(_authored),
      );

      expect(round.radius, closeTo(_authored.radius, 1e-9));
      expect(round.spacing, closeTo(_authored.spacing, 1e-9));
      expect(
        round.typography.body.fontSize,
        closeTo(_authored.typography.body.fontSize!, 1e-9),
      );
    });

    testWidgets('the same component at both scales', (tester) async {
      Future<Size> sizeAt(AdaptiveScaling scaling) async {
        await tester.pumpWidget(
          FastEdgyTheme(
            data: scaling.scale(_authored),
            // Loose constraints, so the chip is measured rather than stretched.
            child: const Center(child: _Chip()),
          ),
        );

        return tester.getSize(find.byType(Padding));
      }

      final desktop = await sizeAt(AdaptiveScaling.desktop);
      final mobile = await sizeAt(AdaptiveScaling.mobile);

      expect(desktop, const Size(56.0, 32.0));
      expect(mobile.width, closeTo(desktop.width * 1.25, 1e-9));
      expect(mobile.height, closeTo(desktop.height * 1.25, 1e-9));
    });
  });

  group('Density', () {
    test('moves the air and nothing else', () {
      final loose = Density.comfortable.apply(_authored);

      expect(loose.spacing, closeTo(4.8, 1e-9));
      expect(loose.radius, _authored.radius);
      expect(loose.typography, _authored.typography);
      expect(loose.density, Density.comfortable);
    });

    test('going back to standard returns the theme that was authored', () {
      final round = Density.standard.apply(Density.compact.apply(_authored));

      expect(round.spacing, closeTo(_authored.spacing, 1e-9));
      expect(round.density, Density.standard);
    });

    test('commutes with the scale — neither axis knows about the other', () {
      final scaleThenPack = Density.compact.apply(
        AdaptiveScaling.mobile.scale(_authored),
      );
      final packThenScale = AdaptiveScaling.mobile.scale(
        Density.compact.apply(_authored),
      );

      expect(scaleThenPack.spacing, closeTo(packThenScale.spacing, 1e-9));
      expect(scaleThenPack.radius, closeTo(packThenScale.radius, 1e-9));
      expect(scaleThenPack.typography, packThenScale.typography);
    });
  });

  group('the fallback', () {
    testWidgets('renders legibly with no application involved', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _Sample(),
        ),
      );

      final text = tester.widget<Text>(find.text('Sample'));

      expect(text.style?.fontSize, FallbackSizes.body);
      expect(text.style?.color, FastEdgyThemeData.fallback.colors.ink);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The sizes the fallback is expected to hold, named so the test reads as an
/// assertion about legibility rather than about a magic number.
abstract final class FallbackSizes {
  static const double body = 14.0;
}

class _Sample extends StatelessWidget {
  const _Sample();

  @override
  Widget build(BuildContext context) {
    final theme = FastEdgyTheme.of(context);

    return ColoredBox(
      color: theme.colors.surface,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing * 2),
        child: Text(
          'Sample',
          style: theme.typography.body.copyWith(color: theme.colors.ink),
        ),
      ),
    );
  }
}
