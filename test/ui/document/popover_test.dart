/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  // A tall editor, so there is room below unless the selection sits low.
  const editor = Rect.fromLTWH(100, 0, 800, 900);
  const overlay = Size(1000, 900);
  const card = Size(richTextPopoverWidth, 240);

  Offset place(
    Rect selection, {
    Size size = card,
    double? width,
    double? height,
    bool avoidToolbar = true,
    bool preferAbove = false,
  }) => RichTextPopoverLayout(
    selection: selection,
    editor: editor,
    width: width ?? richTextPopoverWidth,
    height: height,
    avoidToolbar: avoidToolbar,
    preferAbove: preferAbove,
  ).getPositionForChild(overlay, size);

  group('where a popover lands', () {
    test('under the selection when it fits, the toolbar being above it', () {
      const selection = Rect.fromLTWH(200, 300, 120, 20);

      expect(place(selection).dy, greaterThan(selection.bottom));
      expect(
        place(selection).dy,
        lessThan(selection.bottom + RichTextStyle.toolbarHeight),
      );
    });

    test(
      'above it when there is no room below, ending clear of the toolbar',
      () {
        const selection = Rect.fromLTWH(200, 800, 120, 20);

        // The toolbar's top edge sits a fixed distance above the selection: the
        // card has to end before that edge, not merely before the selection.
        expect(
          place(selection).dy + card.height,
          lessThanOrEqualTo(selection.top - RichTextStyle.toolbarHeight),
        );
      },
    );

    test('right against the line when no toolbar is in the way', () {
      // The toolbar only shows over a range; a list opened on the caret would
      // otherwise stand a toolbar's height clear of nothing at all.
      const selection = Rect.fromLTWH(200, 800, 120, 20);

      final away = place(selection).dy;
      final against = place(selection, avoidToolbar: false).dy;

      expect(against - away, RichTextStyle.toolbarHeight);
      expect(against + card.height, lessThanOrEqualTo(selection.top));
    });

    test('the flip follows the card it is actually given, not a guess', () {
      const selection = Rect.fromLTWH(200, 600, 120, 20);
      const short = Size(richTextPopoverWidth, 180);
      const tall = Size(richTextPopoverWidth, 320);

      // Same selection: the short card still fits under it, the tall one does not.
      expect(place(selection, size: short).dy, greaterThan(selection.bottom));
      expect(
        place(selection, size: tall).dy + tall.height,
        lessThanOrEqualTo(selection.top),
      );
    });

    test(
      'below the toolbar when the selection is too high for it to sit above',
      () {
        const selection = Rect.fromLTWH(200, 4, 120, 20);

        expect(
          place(selection).dy,
          greaterThanOrEqualTo(selection.bottom + RichTextStyle.toolbarSpan),
        );
      },
    );

    test('never past the editor on the left or the right', () {
      expect(
        place(const Rect.fromLTWH(-50, 300, 40, 20)).dx,
        greaterThanOrEqualTo(editor.left),
      );
      expect(
        place(const Rect.fromLTWH(880, 300, 40, 20)).dx + card.width,
        lessThanOrEqualTo(editor.right),
      );
    });
  });

  group('the size a feature asks for', () {
    const selection = Rect.fromLTWH(200, 300, 120, 20);

    test('a wider card is still kept inside the editor', () {
      const wide = 600.0;

      final left = place(
        const Rect.fromLTWH(880, 300, 40, 20),
        size: const Size(wide, 240),
        width: wide,
      ).dx;

      expect(left + wide, lessThanOrEqualTo(editor.right));
    });

    test(
      'the shared width is what a feature gets unless it says otherwise',
      () {
        const layout = RichTextPopoverLayout(
          selection: selection,
          editor: editor,
        );

        expect(
          layout
              .getConstraintsForChild(
                const BoxConstraints(maxWidth: 1000, maxHeight: 900),
              )
              .maxWidth,
          320,
        );
      },
    );

    test(
      'a fixed height is imposed on the card rather than left to its content',
      () {
        const layout = RichTextPopoverLayout(
          selection: selection,
          editor: editor,
          height: 400,
        );

        expect(
          layout
              .getConstraintsForChild(
                const BoxConstraints(maxWidth: 1000, maxHeight: 900),
              )
              .maxHeight,
          400,
        );
      },
    );

    test('relayout follows a size change, not just a move', () {
      const base = RichTextPopoverLayout(selection: selection, editor: editor);

      expect(
        base.shouldRelayout(
          const RichTextPopoverLayout(selection: selection, editor: editor),
        ),
        isFalse,
      );
      expect(
        base.shouldRelayout(
          const RichTextPopoverLayout(
            selection: selection,
            editor: editor,
            width: 600,
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRelayout(
          const RichTextPopoverLayout(
            selection: selection,
            editor: editor,
            height: 400,
          ),
        ),
        isTrue,
      );
    });
  });

  group('a popover over the editor', () {
    setUp(setUpUiTestServices);
    tearDown(resetUiTestServices);

    /// Une carte qu'on remplit est une affordance de bureau — et sous un pouce,
    /// choisir des mots lève aussi le callout du presse-papier, qui n'a rien à
    /// voir avec ce qui est vérifié ici.
    ///
    /// L'override doit être défait avant la fin du corps : le framework vérifie
    /// les drapeaux de debug de la fondation là.
    Future<void> onDesktop(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    /// Opens a card on a selection the editor is holding the focus for, the way
    /// the link button does.
    Future<EditorState> openOverSelection(
      WidgetTester tester, {
      required Widget body,
    }) async {
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(delta: Delta()..insert('Texte'))]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 5,
      );
      state.service.keyboardService?.enable();
      await tester.pumpAndSettle();

      final opened = showRichTextPopover(
        tester.element(find.byType(RichTextEditor)),
        state,
        state.selection!,
        builder: (context, dismiss) => body,
      );
      await tester.pumpAndSettle();

      expect(opened, isTrue);

      return state;
    }

    testWidgets('closes on escape, which the editor would otherwise take', (
      tester,
    ) async {
      // The editor keeps its focus node primary while a card is up, so the card
      // is handed no key at all: Escape reaches the editor, which answers by
      // dropping its selection and leaving the card standing.
      await onDesktop(() async {
        await openOverSelection(tester, body: const Text('carte'));
        expect(find.text('carte'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text('carte'), findsNothing);
      });
    });

    testWidgets('lets a field of its own take the focus from it', (
      tester,
    ) async {
      // The card's scope claims the focus, and stops there: a link card's own
      // field is autofocused inside that scope, which is what fills it in
      // without a click.
      final field = FocusNode(debugLabel: 'card field');
      addTearDown(field.dispose);

      await onDesktop(() async {
        await openOverSelection(
          tester,
          body: TextField(focusNode: field, autofocus: true),
        );

        expect(field.hasPrimaryFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('un callout qui ne prend pas le focus ne le rend pas non plus', (
      tester,
    ) async {
      await onDesktop(() async {
        final state = EditorState(
          document: Document.blank()
            ..insert([0], [paragraphNode(delta: Delta()..insert('Texte'))]),
        );
        addTearDown(state.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: RichTextEditor(
                  features: defaultRichTextFeatures,
                  editorState: state,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        state.selection = Selection.single(
          path: [0],
          startOffset: 0,
          endOffset: 5,
        );
        state.service.keyboardService?.enable();
        await tester.pumpAndSettle();

        final before = FocusManager.instance.primaryFocus;

        showRichTextPopover(
          tester.element(find.byType(RichTextEditor)),
          state,
          state.selection!,
          takesFocus: false,
          builder: (context, dismiss) => const Text('callout'),
        );
        await tester.pumpAndSettle();

        // L'éditeur garde le focus tout du long : le lui rendre le ferait
        // ramener son curseur dans la vue, et la page sauterait sous le doigt.
        expect(FocusManager.instance.primaryFocus, before);
      });
    });

    testWidgets('hands the focus back to the editor when it closes', (
      tester,
    ) async {
      await onDesktop(() async {
        await openOverSelection(tester, body: const Text('carte'));
        final onTheCard = FocusManager.instance.primaryFocus;

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(FocusManager.instance.primaryFocus, isNot(onTheCard));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          contains('keyboard service'),
        );
      });
    });
  });

  // What the toolbar over a selection asks of the same delegate: above the
  // words it acts on, so it does not cover them.
  group('where the toolbar lands', () {
    const bar = Size(320, 40);

    Offset toolbar(Rect selection) => place(
      selection,
      size: bar,
      width: editor.width - 12,
      avoidToolbar: false,
      preferAbove: true,
    );

    test('above the selection rather than over it', () {
      const selection = Rect.fromLTWH(200, 300, 120, 20);

      expect(
        toolbar(selection).dy + bar.height,
        lessThanOrEqualTo(selection.top),
      );
    });

    test('below it when the selection is against the top', () {
      const selection = Rect.fromLTWH(200, 4, 120, 20);

      expect(toolbar(selection).dy, greaterThanOrEqualTo(selection.bottom));
    });

    test('never out of the editor, whichever edge the selection hugs', () {
      for (final selection in [
        const Rect.fromLTWH(100, 300, 40, 20),
        const Rect.fromLTWH(860, 300, 40, 20),
        const Rect.fromLTWH(500, 880, 40, 20),
      ]) {
        final placed = toolbar(selection) & bar;

        expect(
          placed.left,
          greaterThanOrEqualTo(editor.left),
          reason: '$selection',
        );
        expect(
          placed.right,
          lessThanOrEqualTo(editor.right),
          reason: '$selection',
        );
        expect(placed.top, greaterThanOrEqualTo(0), reason: '$selection');
        expect(
          placed.bottom,
          lessThanOrEqualTo(overlay.height),
          reason: '$selection',
        );
      }
    });

    test('no wider than the editor holding it', () {
      const delegate = RichTextPopoverLayout(
        selection: Rect.fromLTWH(200, 300, 120, 20),
        editor: editor,
        width: 788,
        avoidToolbar: false,
        preferAbove: true,
      );

      expect(
        delegate
            .getConstraintsForChild(
              const BoxConstraints(maxWidth: 1000, maxHeight: 900),
            )
            .maxWidth,
        lessThanOrEqualTo(editor.width),
      );
    });
  });
}
