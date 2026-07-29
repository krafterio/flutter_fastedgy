/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = RichTextToolbarTheme.from(RichTextTheme.fallback);

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('thème de la barre', () {
    test('dérive du thème rich text quand personne n\'a rien dit', () {
      expect(base.activeColor, RichTextTheme.fallback.ink);
      expect(base.iconColor, RichTextTheme.fallback.mutedText);
    });

    test('flottante, elle est posée sur la surface partagée', () {
      final floating = RichTextToolbarTheme.from(
        RichTextTheme.fallback,
        docked: false,
      );

      expect(floating.surface, RichTextTheme.fallback.floatingSurface);
    });

    test('ancrée, elle est à fleur : ni ombre ni coins arrondis', () {
      final docked = RichTextToolbarTheme.from(
        RichTextTheme.fallback,
        docked: true,
      );

      expect(docked.surface.boxShadow, anyOf(isNull, isEmpty));
      expect(docked.surface.borderRadius, isNull);
      expect(docked.surface.color, RichTextTheme.fallback.surface);
    });

    test('les cibles grandissent au doigt', () {
      final touch = RichTextToolbarTheme.from(
        RichTextTheme.fallback,
        docked: true,
      );
      final pointer = RichTextToolbarTheme.from(
        RichTextTheme.fallback,
        docked: false,
      );

      expect(touch.itemSize, greaterThan(pointer.itemSize));
      expect(touch.iconSize, greaterThan(pointer.iconSize));
      expect(touch.height, greaterThan(pointer.height));
    });

    test('elle est ancrée sur mobile, flottante ailleurs', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(base.isDocked, isTrue, reason: '$platform');
      }

      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(base.isDocked, isFalse, reason: '$platform');
      }
    });

    test('ce que dit l\'application l\'emporte sur la plateforme', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(base.copyWith(docked: false).isDocked, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(base.copyWith(docked: true).isDocked, isTrue);
    });

    testWidgets('un sous-arbre peut la restyler seule', (tester) async {
      late RichTextToolbarTheme resolved;
      final custom = base.copyWith(
        height: 48,
        padding: const EdgeInsets.all(4),
      );

      await tester.pumpWidget(
        ComponentTheme<RichTextToolbarTheme>(
          data: custom,
          child: Builder(
            builder: (context) {
              resolved = RichTextToolbarTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.height, 48);
      expect(resolved.padding, const EdgeInsets.all(4));
      // Restyling the strip leaves what it is drawn on alone.
      expect(resolved.surface, base.surface);
    });
  });
}
