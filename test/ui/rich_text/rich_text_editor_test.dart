/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  EditorState stateOf(String text) {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
    );
    addTearDown(state.dispose);

    return state;
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  testWidgets('read-only renders where the height is unbounded, as in a list', (
    tester,
  ) async {
    // Two things would throw here: the package's page block wraps its blocks
    // in a scroll view, and the editor always mounts an Overlay. Reading swaps
    // the first for a plain column and measures the second — no caller has to
    // know either.
    await pump(
      tester,
      ListView(
        children: [
          RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Premier message'),
            editable: false,
          ),
          RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Second message'),
            editable: false,
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Premier message', findRichText: true), findsOneWidget);
    expect(find.text('Second message', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'read-only takes the height of what it holds, not the space offered',
    (tester) async {
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Une ligne'),
            editable: false,
          ),
        ),
      );

      expect(tester.getSize(find.byType(RichTextEditor)).height, lessThan(200));
    },
  );

  testWidgets('read-only carries no toolbar', (tester) async {
    await pump(
      tester,
      RichTextEditor(
        features: defaultRichTextFeatures,
        editorState: stateOf('Rendu'),
        editable: false,
      ),
    );

    expect(find.byType(FloatingToolbar), findsNothing);
    expect(find.byType(RichTextDockedToolbar), findsNothing);
  });

  testWidgets('editable docks one on a touch platform', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await pump(
      tester,
      RichTextEditor(
        features: defaultRichTextFeatures,
        editorState: stateOf('Saisie'),
      ),
    );

    // Nothing of the editor's own toolbar under a thumb: that one is wired to
    // the selection and would take the strip away at the first block action.
    expect(find.byType(RichTextDockedToolbar), findsOneWidget);
    expect(find.byType(FloatingToolbar), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('editable carries one, and fills what it is given', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await pump(
      tester,
      RichTextEditor(
        features: defaultRichTextFeatures,
        editorState: stateOf('Saisie'),
      ),
    );

    expect(find.byType(FloatingToolbar), findsOneWidget);
    expect(find.text('Saisie', findRichText: true), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  group('a field with a ceiling', () {
    /// Enough lines to stand taller than any ceiling asked of it here.
    EditorState longDraft() {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [
              for (var line = 0; line < 20; line++)
                paragraphNode(delta: Delta()..insert('Ligne $line')),
            ],
          ),
      );
      addTearDown(state.dispose);

      return state;
    }

    testWidgets('grows with what is written in it while it fits', (
      tester,
    ) async {
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: stateOf('Une ligne'),
            maxHeight: 140,
          ),
        ),
      );

      expect(tester.getSize(find.byType(RichTextEditor)).height, lessThan(140));
    });

    testWidgets('stops at its ceiling and scrolls past it', (tester) async {
      // Without one, a composer pinned under a thread takes a line off the
      // thread for every line typed into it, then overflows the pane.
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: longDraft(),
            maxHeight: 140,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(RichTextEditor)).height, 140);
      expect(
        find.descendant(
          of: find.byType(RichTextEditor),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });
  });

  group('a field that resets when empty', () {
    /// A heading with nothing in it — what `# ` leaves behind once the words
    /// typed after it are deleted back out.
    EditorState emptyHeading() {
      final state = EditorState(
        document: Document.blank()..insert([0], [headingNode(level: 1)]),
      );
      addTearDown(state.dispose);

      return state;
    }

    testWidgets('takes an emptied block back to the paragraph it opens on', (
      tester,
    ) async {
      final state = emptyHeading();
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: state,
          resetWhenEmpty: true,
        ),
      );

      // Whatever edit brought the field there; the field reads the document it
      // is left with, not the edit.
      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 0, ''),
      );
      await tester.pumpAndSettle();

      expect(state.document.root.children, hasLength(1));
      expect(state.document.root.children.first.type, ParagraphBlockKeys.type);
    });

    testWidgets('leaves a block that still says something alone', (
      tester,
    ) async {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [headingNode(level: 1, delta: Delta()..insert('Titre'))],
          ),
      );
      addTearDown(state.dispose);
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: state,
          resetWhenEmpty: true,
        ),
      );

      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 5, ' !'),
      );
      await tester.pumpAndSettle();

      expect(state.document.root.children.first.type, HeadingBlockKeys.type);
    });

    testWidgets('a page keeps its emptied heading, which is a heading still', (
      tester,
    ) async {
      final state = emptyHeading();
      await pump(
        tester,
        RichTextEditor(features: defaultRichTextFeatures, editorState: state),
      );

      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 0, ''),
      );
      await tester.pumpAndSettle();

      expect(state.document.root.children.first.type, HeadingBlockKeys.type);
    });
  });

  group('a field that sends on Enter', () {
    /// Puts the caret at the end of the only block, the way typing into the
    /// field would leave it.
    Future<void> pumpComposer(
      WidgetTester tester,
      EditorState state, {
      required VoidCallback onSubmit,
    }) async {
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: state,
          onSubmit: onSubmit,
        ),
      );
      state.selection = Selection.collapsed(
        Position(
          path: [0],
          offset: state.document.root.children.first.delta!.length,
        ),
      );
      await tester.pump();
    }

    testWidgets('Enter sends rather than opening a line', (tester) async {
      final state = stateOf('Bien vu');
      var sent = 0;
      await pumpComposer(tester, state, onSubmit: () => sent++);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, 1);
      expect(state.document.root.children, hasLength(1));
    });

    testWidgets('the modifier opens the line Enter would have opened', (
      tester,
    ) async {
      final state = stateOf('Bien vu');
      var sent = 0;
      await pumpComposer(tester, state, onSubmit: () => sent++);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(sent, 0);
      expect(state.document.root.children, hasLength(2));
    });

    testWidgets('a block that keeps its own line breaks keeps Enter', (
      tester,
    ) async {
      // Enter inside a code block writes a line of code; sending the message
      // somebody is in the middle of writing is the one thing it must not do.
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [codeBlockNode(delta: Delta()..insert('print("hi")'))]),
      );
      addTearDown(state.dispose);
      var sent = 0;
      await pumpComposer(tester, state, onSubmit: () => sent++);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, 0);
    });
  });

  group('a page being left', () {
    testWidgets('lets the frame that unmounts it finish first', (tester) async {
      final state = stateOf('Une note');
      final key = GlobalKey<RichTextEditorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              key: key,
              features: defaultRichTextFeatures,
              editorState: state,
              scrollable: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final controller = key.currentState!.scrollController;

      // What the list under the editor does: a scroll schedules a write of
      // where its items landed, run once the frame is over. A page left while
      // it scrolls unmounts in that very frame.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => controller.offsetNotifier.value = 12,
      );

      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ce que le paquet fait planter', () {
    testWidgets('un déclencheur ne lit pas au-delà de sa ligne', (
      tester,
    ) async {
      final state = stateOf('Mars');
      await pump(
        tester,
        RichTextEditor(features: defaultRichTextFeatures, editorState: state),
      );

      // Le service de saisie applique ce qui est tapé sur un debounce, donc le
      // curseur a pu bouger quand le déclencheur tourne. Il lisait la ligne
      // jusqu'au curseur avec `substring`, qui lève au lieu de dire non.
      state.selection = Selection.collapsed(Position(path: [0], offset: 12));

      final trigger = tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .characterShortcutEvents
          .firstWhere(
            (event) => event.key.startsWith(formatAsteriskToBulletedList.key),
          );

      expect(await trigger.handler(state), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une page a toujours de quoi chercher sous un doigt', (
      tester,
    ) async {
      final state = stateOf('Mars');
      await pump(
        tester,
        SizedBox(
          height: 300,
          child: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: state,
            scrollable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La recherche du bloc sous le doigt finit sur `clamp(premier, dernier)`,
      // et une page ne dit rien de visible tant que sa liste n'a pas répondu :
      // dernier valait -1, et clamp lève.
      final range = tester
          .state<RichTextEditorState>(find.byType(RichTextEditor))
          .scrollController
          .visibleRangeNotifier;

      expect(range.value.$2, greaterThanOrEqualTo(0));
    });
  });

  group('ce que la frappe met en forme', () {
    testWidgets('un dièse reste un dièse', (tester) async {
      // Un « # » est un caractère qu'on écrit — un numéro, un mot-clé — et le
      // seul endroit où on l'écrit est celui où il passait pour un titre : en
      // tête d'une ligne qu'on vient d'ouvrir.
      await pump(
        tester,
        RichTextEditor(
          features: defaultRichTextFeatures,
          editorState: stateOf('Salut'),
        ),
      );

      final keys = tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .characterShortcutEvents
          .map((event) => event.key);

      expect(
        keys.where((key) => key.startsWith(formatSignToHeading.key)),
        isEmpty,
      );

      // Les autres continuent : leur marqueur n'ouvre pas de phrase.
      expect(
        keys.where((key) => key.startsWith(formatMinusToBulletedList.key)),
        isNotEmpty,
      );
      expect(
        keys.where((key) => key.startsWith(formatNumberToNumberedList.key)),
        isNotEmpty,
      );
    });
  });

  group('ce que l\'historique retient', () {
    testWidgets('un tableau qui se met en forme n\'est pas une frappe', (
      tester,
    ) async {
      // Un tableau stocké sans ses largeurs de colonnes les écrit dans le
      // document en se posant. Le document s'ouvrait alors avec un bouton
      // annuler vivant, prêt à défaire ce qui venait d'être chargé.
      const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);
      final state = EditorState(
        document: codec.decode('| A | B |\n|---|---|\n| 1 | 2 |'),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
              scrollable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(state.undoManager.undoStack.isEmpty, isTrue);
    });

    testWidgets('ce qui est tapé, si', (tester) async {
      const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);
      final state = EditorState(document: codec.decode('Bonjour'));
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
              scrollable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      state.selection = Selection.collapsed(Position(path: [0], offset: 7));
      await state.apply(
        state.transaction
          ..insertText(state.document.root.children.first, 7, ' Monde'),
      );
      await tester.pumpAndSettle();

      expect(state.undoManager.undoStack.isNonEmpty, isTrue);
    });
  });

  testWidgets('the right-click menu does not wake the bar mid-build', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final state = stateOf('Some text to cut');

    await pump(
      tester,
      RichTextEditor(features: defaultRichTextFeatures, editorState: state),
    );

    // The floating bar is up: it is the one listening to the flag the menu
    // raises as it mounts, from inside a build.
    state.selection = Selection.single(path: [0], startOffset: 0, endOffset: 2);
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byType(RichTextEditor)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}
