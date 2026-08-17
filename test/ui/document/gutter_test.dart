/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(() {
    resetUiTestServices();
    forceShowBlockAction = false;
  });

  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;

    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<EditorState> pumpPage(
    WidgetTester tester, {
    DocumentLayout? mounted,
    Widget? header,
  }) async {
    final state = EditorState(
      document: markdownToDocument('Un\n\nDeux\n\nTrois'),
    );
    addTearDown(state.dispose);

    final editor = DocumentEditor(editorState: state, header: header);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: mounted == null
              ? editor
              : ComponentTheme<DocumentLayout>(data: mounted, child: editor),
        ),
      ),
    );
    await tester.pump();

    return state;
  }

  Future<void> caretOn(
    WidgetTester tester,
    EditorState state,
    int block,
  ) async {
    state.selection = Selection.collapsed(Position(path: [block]));
    await tester.pumpAndSettle();
  }

  Finder handles(FastEdgyGlyph glyph) =>
      find.byIcon(FastEdgyIcons.material[glyph]);

  double topOfSecondBlock(WidgetTester tester) =>
      tester.getTopLeft(find.text('Deux', findRichText: true)).dy;

  group('la gouttière au doigt', () {
    // The editor only shows a block's gutter while it is hovered, and a finger
    // hovers nothing: without this the gutter would never be there at all.
    testWidgets('l\'éditeur lève le verrou du survol', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);

        expect(forceShowBlockAction, isTrue);
      });
    });

    testWidgets('elle ne se montre que sur le bloc qu\'on écrit', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpPage(tester);

        expect(handles(FastEdgyGlyph.gripRow), findsNothing);

        await caretOn(tester, state, 1);
        expect(handles(FastEdgyGlyph.gripRow), findsOneWidget);

        await caretOn(tester, state, 2);
        expect(handles(FastEdgyGlyph.gripRow), findsOneWidget);

        state.selection = null;
        await tester.pumpAndSettle();
        expect(handles(FastEdgyGlyph.gripRow), findsNothing);
      });
    });

    testWidgets('une poignée, pas deux boutons dans la marge', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpPage(tester);
        await caretOn(tester, state, 0);

        expect(handles(FastEdgyGlyph.add), findsNothing);
        expect(handles(FastEdgyGlyph.gripRow), findsOneWidget);
      });
    });

    testWidgets('elle ne coûte pas plus de place qu\'au pointeur', (
      tester,
    ) async {
      late double pointer;

      await onPlatform(TargetPlatform.macOS, () async {
        await pumpPage(tester);
        pointer = topOfSecondBlock(tester);
      });

      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpPage(tester);
        await caretOn(tester, state, 0);

        expect(topOfSecondBlock(tester), pointer);
      });
    });

    testWidgets('la tenir déplace vraiment le bloc', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpPage(tester);
        await caretOn(tester, state, 0);

        final handle = tester.getCenter(handles(FastEdgyGlyph.gripRow));
        final third = tester.getCenter(find.text('Trois', findRichText: true));

        final gesture = await tester.startGesture(handle);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveTo(third);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          state.document.root.children.map((node) => node.delta?.toPlainText()),
          ['Deux', 'Trois', 'Un'],
        );
      });
    });

    testWidgets('la toucher ouvre son menu', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpPage(tester);
        await caretOn(tester, state, 0);

        expect(find.byType(LongPressDraggable<Node>), findsOneWidget);
        expect(find.byType(Draggable<Node>), findsNothing);

        await tester.tap(handles(FastEdgyGlyph.gripRow));
        await tester.pumpAndSettle();

        expect(find.text(t('Insert a paragraph below')), findsWidgets);
      });
    });

    testWidgets('le menu insère bien le paragraphe', (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final state = await pumpPage(tester);
        await caretOn(tester, state, 0);

        await tester.tap(handles(FastEdgyGlyph.gripRow));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t('Insert a paragraph below')).last);
        await tester.pumpAndSettle();

        expect(state.document.root.children, hasLength(4));
        expect(state.getNodeAtPath([1])?.delta?.toPlainText(), isEmpty);
      });
    });
  });

  group('la colonne que la gouttière occupe', () {
    testWidgets('la page suit la mise en page montée par l\'application', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final phone = DocumentLayout.standard.copyWith(horizontalPadding: 24);
        final state = await pumpPage(
          tester,
          mounted: phone,
          header: const SizedBox(width: double.infinity, child: Text('Titre')),
        );
        await caretOn(tester, state, 0);

        final text = tester.getTopLeft(find.text('Un', findRichText: true)).dx;

        expect(text, tester.getTopLeft(find.text('Titre')).dx);
        expect(
          tester.getTopLeft(handles(FastEdgyGlyph.gripRow)).dx,
          lessThan(text),
        );
      });
    });
  });

  group('la gouttière au pointeur', () {
    testWidgets('les deux boutons restent dans la marge', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await pumpPage(tester);

        expect(forceShowBlockAction, isFalse);
        expect(handles(FastEdgyGlyph.add), findsNWidgets(3));
        expect(handles(FastEdgyGlyph.gripRow), findsNWidgets(3));
      });
    });

    testWidgets('la poignée part au premier mouvement', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await pumpPage(tester);

        expect(find.byType(Draggable<Node>), findsNWidgets(3));
        expect(find.byType(LongPressDraggable<Node>), findsNothing);
      });
    });
  });
}
