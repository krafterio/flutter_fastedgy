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

    test('scales the heading role, level by level', () {
      const tokens = FastEdgyThemeData(
        typography: TypographyRoles(
          body: TextStyle(fontSize: 14),
          blockText: TextStyle(fontSize: 16),
          small: TextStyle(fontSize: 12),
          mono: TextStyle(fontSize: 13),
          heading: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      );
      final heading = RichTextTheme.from(tokens).headingText;

      expect(heading, hasLength(6));
      expect(heading[0].fontSize, greaterThan(heading[1].fontSize!));
      expect(heading[2].fontSize, 20 * RichTextTheme.defaultHeadingScale[2]);
      expect(
        heading.every((style) => style.fontWeight == FontWeight.w600),
        isTrue,
      );
      expect(
        heading.every((style) => style.color == null),
        isTrue,
        reason: 'a colour here would repaint an inline colour in the heading',
      );
    });

    test('takes the scale an application names, as far as it names it', () {
      final loud = RichTextTheme.from(
        FastEdgyThemeData.fallback,
        headingScale: const [2.0, 1.5, 1.0],
      );
      final role = FastEdgyThemeData.fallback.typography.heading.fontSize!;

      expect(loud.headingText, hasLength(3));
      expect(loud.headingAt(1).fontSize, role * 2);
      expect(loud.headingAt(5).fontSize, role, reason: 'clamped to the last');
    });

    test('answers for a level no toolbar makes', () {
      final theme = RichTextTheme.fallback;

      expect(theme.headingAt(6), theme.headingText.last);
      expect(theme.headingAt(9), theme.headingText.last);
      expect(theme.headingAt(1), theme.headingText.first);
      expect(theme.headingAt(0), theme.headingText.first);
      expect(
        theme.copyWith(headingText: const []).headingAt(2),
        theme.blockText,
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
