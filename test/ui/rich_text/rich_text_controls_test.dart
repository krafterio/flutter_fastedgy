/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RichTextControls', () {
    testWidgets('draws with the fallback when nothing is supplied', (
      tester,
    ) async {
      var tapped = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => RichTextControls.of(context).tappable(
              context,
              RichTextTapSpec(
                onTap: () => tapped++,
                child: const Text('copier'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('copier'));
      expect(tapped, 1, reason: 'a package is usable before an app writes one');
    });

    testWidgets('an application replaces the rendering, not the behaviour', (
      tester,
    ) async {
      var tapped = 0;

      final controls = RichTextControls.fallback.copyWith(
        tappable: (context, spec) => GestureDetector(
          onTap: spec.onTap,
          child: ColoredBox(color: const Color(0xFFAABBCC), child: spec.child),
        ),
        picker: (context, spec) => const SizedBox(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ComponentTheme<RichTextControls>(
            data: controls,
            child: Builder(
              builder: (context) => RichTextControls.of(context).tappable(
                context,
                RichTextTapSpec(
                  onTap: () => tapped++,
                  child: const Text('copier'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(
        tester
            .widget<ColoredBox>(
              find
                  .ancestor(
                    of: find.text('copier'),
                    matching: find.byType(ColoredBox),
                  )
                  .first,
            )
            .color,
        const Color(0xFFAABBCC),
      );

      await tester.tap(find.text('copier'));
      expect(tapped, 1, reason: 'the module still owns what a tap does');
    });

    testWidgets('a picker hands its choices, not a menu', (tester) async {
      final offered = <RichTextPickerOption>[];
      String? chosen = 'before';

      final controls = RichTextControls.fallback.copyWith(
        picker: (context, spec) {
          offered.addAll(spec.options);

          return TextButton(
            onPressed: () => spec.onSelect(spec.options.last.value),
            child: Text(spec.label),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ComponentTheme<RichTextControls>(
            data: controls,
            child: Builder(
              builder: (context) => RichTextControls.of(context).picker(
                context,
                RichTextPickerSpec(
                  label: 'Auto',
                  selected: null,
                  onSelect: (value) => chosen = value,
                  options: const [
                    RichTextPickerOption(value: null, label: 'Auto'),
                    RichTextPickerOption(value: 'dart', label: 'Dart'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(offered.map((o) => o.label), ['Auto', 'Dart']);

      await tester.tap(find.text('Auto'));
      expect(chosen, 'dart');
    });
  });

  group('FastEdgyIcons', () {
    testWidgets('one set reaches every block that draws a glyph', (
      tester,
    ) async {
      late FastEdgyIcons resolved;

      await tester.pumpWidget(
        ComponentTheme<FastEdgyIcons>(
          data: const FastEdgyIcons({
            FastEdgyGlyph.check: Icons.done_all,
            FastEdgyGlyph.copy: Icons.content_copy,
          }),
          child: Builder(
            builder: (context) {
              resolved = FastEdgyIcons.of(context);

              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved[FastEdgyGlyph.check], Icons.done_all);
      expect(resolved[FastEdgyGlyph.copy], Icons.content_copy);
      expect(
        resolved[FastEdgyGlyph.unlink],
        Icons.link_off,
        reason: 'naming two glyphs is not naming the seventeen',
      );
    });

    testWidgets('falls back to Material where nothing was mounted', (
      tester,
    ) async {
      late FastEdgyIcons resolved;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            resolved = FastEdgyIcons.of(context);

            return const SizedBox();
          },
        ),
      );

      expect(resolved, FastEdgyIcons.material);
    });
  });

  group('CodeBlockTheme', () {
    test('derives a legible palette from the roles alone', () {
      final derived = CodeBlockTheme.from(RichTextTheme.fallback);

      expect(derived.text, RichTextTheme.fallback.codeText);
      expect(derived.syntax['keyword']?.color, RichTextTheme.fallback.link);
      expect(derived.syntax['comment']?.fontStyle, FontStyle.italic);
    });

    test('a scope nobody styled falls back to plain code text', () {
      final derived = CodeBlockTheme.from(RichTextTheme.fallback);

      expect(
        derived.syntax['something-upstream-invented'],
        isNull,
        reason: 'a partial map is valid — the renderer draws the rest as text',
      );
    });
  });
}
