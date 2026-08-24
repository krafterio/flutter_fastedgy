/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

EditorState _stateOf(String text) => EditorState(
  document: Document.blank()..insert([0], [paragraphNode(text: text)]),
);

void main() {
  group('showRichTextPopover', () {
    testWidgets('draws with the theme the caller had, not the fallback', (
      tester,
    ) async {
      final registered = RichTextTheme.fallback.copyWith(
        floatingSurface: const BoxDecoration(color: Color(0xFF123456)),
      );

      final state = _stateOf('Une ligne');
      late BuildContext editorContext;

      await tester.pumpWidget(
        MaterialApp(
          home: ComponentTheme<RichTextTheme>(
            data: registered,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  editorContext = context;

                  return RichTextEditor(
                    editorState: state,
                    features: const RichTextFeatures([]),
                  );
                },
              ),
            ),
          ),
        ),
      );

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 5,
      );
      await tester.pumpAndSettle();

      final opened = showRichTextPopover(
        editorContext,
        state,
        state.selection!,
        builder: (context, dismiss) => const Text('carte'),
      );
      expect(opened, isTrue);
      await tester.pumpAndSettle();

      // The card lives in the root overlay, outside the subtree that carries the
      // theme. Without InheritedTheme.capture this reads the fallback instead.
      final card = tester.widget<Container>(
        find
            .ancestor(of: find.text('carte'), matching: find.byType(Container))
            .first,
      );

      expect((card.decoration as BoxDecoration).color, const Color(0xFF123456));

      state.dispose();
    });
  });

  group('RichTextPopoverLayout', () {
    const editor = Rect.fromLTWH(35, 0, 332, 800);
    const selection = Rect.fromLTWH(60, 400, 40, 20);

    Offset positionOf(Size childSize) => const RichTextPopoverLayout(
      selection: selection,
      editor: editor,
    ).getPositionForChild(const Size(402, 874), childSize);

    test('une carte plus large que l\'éditeur se cale contre son bord', () {
      // Une barre de boutons est plus large qu'un téléphone : il n'y a pas de
      // place où elle commence et finit dans l'éditeur, et borner entre deux
      // bornes croisées lève une ArgumentError qui emportait tout l'éditeur.
      final position = positionOf(const Size(320, 52));

      expect(position.dx, greaterThanOrEqualTo(editor.left));
      expect(position.dx, lessThan(selection.left));
    });

    test('et une carte qui tient suit la sélection', () {
      final position = positionOf(const Size(120, 52));

      expect(position.dx, selection.left);
    });

    test('sans jamais dépasser le bord droit', () {
      final position = positionOf(const Size(280, 52));

      expect(position.dx + 280, lessThanOrEqualTo(editor.right));
    });
  });

  group('la place laissée au callout', () {
    const editor = Rect.fromLTWH(0, 0, 390, 844);
    const selection = Rect.fromLTWH(60, 400, 40, 20);

    double topOf({required double reserveAbove}) => RichTextPopoverLayout(
      selection: selection,
      editor: editor,
      avoidToolbar: false,
      preferAbove: true,
      reserveAbove: reserveAbove,
    ).getPositionForChild(const Size(390, 844), const Size(320, 52)).dy;

    test('une barre qui doit passer au-dessus monte d\'autant', () {
      // Sous un pouce, le callout du presse-papier prend la place juste
      // au-dessus des mots ; la barre se pose par-dessus lui, pas dessus eux.
      expect(
        topOf(reserveAbove: 0) - topOf(reserveAbove: 48),
        closeTo(48, 0.5),
      );
    });

    test('et rien à réserver la laisse contre les mots', () {
      expect(topOf(reserveAbove: 0) + 52, lessThanOrEqualTo(selection.top));
    });
  });

  group('RichTextSurface', () {
    testWidgets('écrit avec le style du thème, pas avec celui du dessus', (
      tester,
    ) async {
      final theme = RichTextTheme.fallback;
      late TextStyle inside;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          // Ce que voit une surface montée dans un overlay : le style de
          // secours du framework, gras et souligné de jaune.
          child: DefaultTextStyle(
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFFFFF00),
            ),
            child: ComponentTheme<RichTextTheme>(
              data: theme,
              child: const RichTextSurface(child: _StyleProbe()),
            ),
          ),
        ),
      );

      inside = _StyleProbe.seen!;
      expect(inside.decoration, isNot(TextDecoration.underline));
      expect(inside.fontWeight, theme.fieldText.fontWeight);
      expect(inside.fontSize, theme.fieldText.fontSize);
    });
  });
}

class _StyleProbe extends StatelessWidget {
  static TextStyle? seen;

  const _StyleProbe();

  @override
  Widget build(BuildContext context) {
    seen = DefaultTextStyle.of(context).style;

    return const SizedBox.shrink();
  }
}
