/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RichTextTheme', () {
    test('is fully drawable with nothing supplied', () {
      final theme = RichTextTheme.fallback;

      expect(theme.blockText.fontSize, isNotNull);
      expect(theme.blockText.color, isNotNull);
      expect(theme.fieldText.color, isNotNull);
      expect(theme.codeText.color, isNotNull);
      expect(theme.monoFontFamily, isNull, reason: 'the floor names no family');
      expect(theme.blockRadius, isNot(BorderRadius.zero));
      expect(theme.blockPadding, isNot(EdgeInsets.zero));
    });

    test('derives every value from the tokens', () {
      const tokens = FastEdgyThemeData(radius: 12.0, spacing: 5.0);
      final derived = RichTextTheme.from(tokens);

      expect(derived.ink, tokens.colors.ink);
      expect(derived.subtleSurface, tokens.colors.subtleSurface);
      expect(derived.selection, tokens.colors.selection);
      expect(derived.blockRadius, BorderRadius.circular(12.0));
      expect(derived.chipRadius, BorderRadius.circular(6.0));
      expect(derived.blockPadding.left, 15.0);
      expect(derived.blockText.fontSize, tokens.typography.blockText.fontSize);
    });

    test('pushes the selection toward the ink over a block with a surface', () {
      final theme = RichTextTheme.fallback;
      final ink = theme.ink.computeLuminance();

      expect(
        theme.selectionOnSurface,
        isNot(theme.selection),
        reason: 'a selected line inside a code block has to read as selected',
      );

      // Toward the ink, not simply darker: on a dark theme the ink is the pale
      // end, and a rule that always darkened would lose the contrast there.
      expect(
        (theme.selectionOnSurface.computeLuminance() - ink).abs(),
        lessThan((theme.selection.computeLuminance() - ink).abs()),
      );
    });

    test('copyWith touches one value and leaves the rest', () {
      final red = RichTextTheme.fallback.copyWith(
        cursor: const Color(0xFFFF0000),
      );

      expect(red.cursor, const Color(0xFFFF0000));
      expect(red.selection, RichTextTheme.fallback.selection);
      expect(red.blockText, RichTextTheme.fallback.blockText);
    });

    testWidgets('follows a token an application overrides', (tester) async {
      late RichTextTheme resolved;

      await tester.pumpWidget(
        FastEdgyTheme(
          data: FastEdgyThemeData.fallback.copyWith(
            colors: ColorRoles.fallback.copyWith(ink: const Color(0xFF112233)),
          ),
          child: Builder(
            builder: (context) {
              resolved = RichTextTheme.of(context);

              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved.ink, const Color(0xFF112233));
      expect(resolved.blockText.color, const Color(0xFF112233));
    });

    testWidgets('what the application registered wins over the tokens', (
      tester,
    ) async {
      late RichTextTheme resolved;

      final registered = RichTextTheme.fallback.copyWith(
        selection: const Color(0xFF00FF00),
      );

      await tester.pumpWidget(
        FastEdgyTheme(
          data: FastEdgyThemeData.fallback,
          child: ComponentTheme<RichTextTheme>(
            data: registered,
            child: Builder(
              builder: (context) {
                resolved = RichTextTheme.of(context);

                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(resolved.selection, const Color(0xFF00FF00));
    });
  });
}
