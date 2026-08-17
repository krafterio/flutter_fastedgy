/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pale card and a selection a step off it, which is the shape the problem
/// takes wherever a code block is drawn on a surface of its own.
final _theme = RichTextTheme.from(
  FastEdgyThemeData.fallback.copyWith(
    colors: ColorRoles.fallback.copyWith(
      subtleSurface: const Color(0xFFF1F1EF),
      selection: const Color(0xFFECECEA),
    ),
  ),
);

void main() {
  /// How far apart two colours read, on the 0–1 scale a screen shows them at.
  double apart(dynamic a, dynamic b) =>
      (a.computeLuminance() as double) - (b.computeLuminance() as double);

  group('the selection over a block with a surface of its own', () {
    test('stands out from the card it is laid on', () {
      // The report that made this a test: selected code looked unselected. The
      // editor's own tint and the card are barely a step apart, so the
      // highlight read as grey on grey and nothing showed what was about to be
      // deleted.
      expect(
        apart(_theme.subtleSurface, _theme.selection).abs(),
        lessThan(0.05),
      );
      expect(
        apart(_theme.subtleSurface, _theme.selectionOnSurface),
        greaterThan(0.1),
      );
    });

    test('stays the neutral the rest of the selection is', () {
      // Darkened, never recoloured: a selection running through a code block
      // and the text around it has to read as one selection.
      final tint = _theme.selectionOnSurface;

      expect((tint.r - tint.g).abs(), lessThan(0.02));
      expect((tint.r - tint.b).abs(), lessThan(0.05));
    });

    test('is darker than the one laid on the page', () {
      expect(
        apart(_theme.selection, _theme.selectionOnSurface),
        greaterThan(0.1),
      );
    });
  });
}
