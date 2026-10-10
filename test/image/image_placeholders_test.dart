/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _dark = ColorRoles(
  ink: Color(0xFFF4F4F5),
  muted: Color(0xFFA1A1AA),
  surface: Color(0xFF18181B),
  subtleSurface: Color(0xFF27272A),
  border: Color(0xFF3F3F46),
  subtleBorder: Color(0xFF27272A),
  accent: Color(0xFFE4E4E7),
  onAccent: Color(0xFF18181B),
  danger: Color(0xFFF87171),
  success: Color(0xFF4ADE80),
  selection: Color(0x33E4E4E7),
  cursor: Color(0xFFF4F4F5),
);

Widget _themed(Widget Function(BuildContext) builder) => Directionality(
  textDirection: TextDirection.ltr,
  child: FastEdgyTheme(
    data: const FastEdgyThemeData(colors: _dark),
    child: Builder(builder: builder),
  ),
);

Color? _colorOf(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container).first).color;

void main() {
  testWidgets(
    'draws the loading placeholder with the roles of the theme in scope',
    (tester) async {
      await tester.pumpWidget(
        _themed((context) => const ImagePlaceholders().loading(context)),
      );

      expect(_colorOf(tester), _dark.ink.withValues(alpha: 0.12));
    },
  );

  testWidgets(
    'draws the missing image with the roles and the glyph of the theme in scope',
    (tester) async {
      await tester.pumpWidget(
        _themed((context) => const ImagePlaceholders().error(context)),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));

      expect(_colorOf(tester), _dark.subtleSurface);
      expect(icon.icon, FastEdgyIcons.material[FastEdgyGlyph.imageMissing]);
      expect(icon.color, _dark.muted);
    },
  );
}
