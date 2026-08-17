/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

/// The floor's glyphs, and they are distinct on purpose: a row grip and a
/// column grip drawn alike are two affordances nobody can tell apart.
const _rowGrip = Icons.drag_indicator;
const _columnGrip = Icons.drag_handle;

/// Nothing supplied: the module draws with the floor, which is what a package
/// has to be usable on.
Widget _themed(Widget child) => child;

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  /// A paragraph, then a two-by-two table whose second column is empty.
  Node tableOf() => TableNode.fromList([
    [paragraphNode(delta: Delta()..insert('Test')), paragraphNode()],
    [paragraphNode(delta: Delta()..insert('Col 2')), paragraphNode()],
  ]).node;

  Future<Node> pump(WidgetTester tester) async {
    final table = tableOf();
    final state = EditorState(
      document: Document.blank()..insert([0], [paragraphNode(), table]),
    );
    // The package seals a history item on a timer after every transaction, and
    // measuring the table's rows applies one: a test that ends before it fires
    // fails on the pending timer whatever it asserted.
    state.disableSealTimer = true;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _themed(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
              toolbar: false,
              hintPlaceholder: 'Écrivez ici',
              // What hangs in a block's left margin on a page — the handle a
              // block is dragged by.
              blockActions: (blockContext, builder) => const Text('poignée'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The cursor in the empty cell of the first row.
    state.selection = Selection.collapsed(
      Position(path: table.children[1].children.first.path, offset: 0),
    );
    await tester.pump();
    await tester.pump();

    // Nothing of the editor may outlive the test — it leaves a blinking cursor
    // behind, and a pending timer fails the test whatever it asserted.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    return table;
  }

  testWidgets('an empty cell holding the cursor shows no placeholder', (
    tester,
  ) async {
    // The hint is written for the width of a page and a cell is a column of its
    // own: it wrapped over four lines in one.
    await pump(tester);

    expect(find.text('Écrivez ici', findRichText: true), findsNothing);
  });

  testWidgets('and so keeps the row the height of the row beside it', (
    tester,
  ) async {
    // The package measures a row from what its cells draw, and stores it. The
    // wrapped hint pushed the row open, and the height stayed once the cursor
    // had left — the table came back with one row half as tall again.
    final table = await pump(tester);
    final heights = table.children
        .map((cell) => cell.attributes[TableCellBlockKeys.height])
        .toSet();

    expect(heights, hasLength(1));
  });

  testWidgets('no cell carries the affordances a block on the page has', (
    tester,
  ) async {
    // A cell has no margin to put them in: they landed over the table's own
    // row and column handles.
    await pump(tester);

    // One for the paragraph above, one for the table itself — none inside it.
    expect(find.text('poignée'), findsNWidgets(2));
  });

  // A table measures its rows on arrival and records what it measured, so a
  // transaction fires on open with nothing written. A screen that takes every
  // transaction for an edit declares the note changed before it is touched.
  testWidgets('monter un tableau ne change pas ce que le document dit', (
    tester,
  ) async {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);
    final table = tableOf();
    final document = Document.blank()..insert([0], [paragraphNode(), table]);
    final before = codec.encode(document);

    final state = EditorState(document: document);
    state.disableSealTimer = true;
    addTearDown(state.dispose);

    var transactions = 0;
    final edits = state.transactionStream.listen((_) => transactions++);
    addTearDown(edits.cancel);

    await tester.pumpWidget(
      _themed(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
              toolbar: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    expect(transactions, greaterThan(0), reason: 'rien ne serait à prouver');
    expect(codec.encode(state.document), before);
  });

  group('les poignées au doigt', () {
    Future<(EditorState, Node)> pumpTable(WidgetTester tester) async {
      final table = tableOf();
      final state = EditorState(
        document: Document.blank()..insert([0], [paragraphNode(), table]),
      );
      state.disableSealTimer = true;
      addTearDown(state.dispose);

      await tester.pumpWidget(
        _themed(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
                toolbar: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });

      return (state, table);
    }

    Future<void> caretIn(
      WidgetTester tester,
      EditorState state,
      Node cell,
    ) async {
      state.selection = Selection.collapsed(
        Position(path: cell.children.first.path, offset: 0),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('écrire dans une cellule les fait venir, sans survol', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);

      expect(find.byIcon(_rowGrip), findsNothing);
      expect(find.byIcon(_columnGrip), findsNothing);

      await caretIn(tester, state, table.children.first);

      expect(find.byIcon(_rowGrip), findsOneWidget);
      expect(find.byIcon(_columnGrip), findsOneWidget);
    });

    testWidgets('elles suivent la cellule qu\'on écrit', (tester) async {
      final (state, table) = await pumpTable(tester);

      await caretIn(tester, state, table.children.first);
      final first = tester.getRect(find.byIcon(_rowGrip));

      await caretIn(tester, state, table.children[1]);

      expect(tester.getRect(find.byIcon(_rowGrip)), isNot(first));
    });

    testWidgets('elles partent quand le caret quitte le tableau', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);

      await caretIn(tester, state, table.children.first);
      expect(find.byIcon(_columnGrip), findsOneWidget);

      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(_rowGrip), findsNothing);
      expect(find.byIcon(_columnGrip), findsNothing);
    });

    Offset edgeOf(Node cell) {
      final box = cell.renderBox!;
      final rect = box.localToGlobal(Offset.zero) & box.size;

      return Offset(rect.right, rect.center.dy);
    }

    testWidgets('un bord intérieur se prend et élargit sa colonne', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children.first);

      final before = TableNode(node: table).getColWidth(0);

      await tester.dragFrom(edgeOf(table.children.first), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(TableNode(node: table).getColWidth(0), greaterThan(before));
    });

    testWidgets('chaque bord est le sien, où que soit le caret', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children[2]);

      final first = TableNode(node: table).getColWidth(0);
      final second = TableNode(node: table).getColWidth(1);

      await tester.dragFrom(edgeOf(table.children.first), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(TableNode(node: table).getColWidth(0), greaterThan(first));
      expect(TableNode(node: table).getColWidth(1), second);
    });

    testWidgets('toute la pastille répond, pas seulement son glyphe', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children.first);

      final chip = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(_rowGrip),
              matching: find.byType(GestureDetector),
            )
            .first,
      );

      await tester.tapAt(chip.center);
      await tester.pumpAndSettle();

      expect(find.text(t('Insert a row above')), findsOneWidget);
    });

    testWidgets('la pastille d\'une autre ligne répond de la même façon', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children[1]);

      final chip = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(_rowGrip),
              matching: find.byType(GestureDetector),
            )
            .first,
      );

      await tester.tapAt(chip.center);
      await tester.pumpAndSettle();

      expect(find.text(t('Insert a row above')), findsOneWidget);
    });

    testWidgets('les boutons d\'ajout sont là, et ils ajoutent', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children.first);

      final adders = find.byIcon(Icons.add);

      expect(adders, findsNWidgets(2));

      final columns = TableNode(node: table).colsLen;

      await tester.tap(adders.first);
      await tester.pumpAndSettle();

      expect(TableNode(node: table).colsLen, columns + 1);
    });

    testWidgets('ouvrir le menu ne fait pas perdre le caret ni les poignées', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children.first);

      final caret = state.selection;

      await tester.tap(find.byIcon(_rowGrip));
      await tester.pumpAndSettle();

      expect(state.selection, caret);
      expect(find.byIcon(_rowGrip), findsOneWidget);
      expect(find.byIcon(_columnGrip), findsOneWidget);
    });

    testWidgets('elles restent dans le tableau, comme celles du pointeur', (
      tester,
    ) async {
      final (state, table) = await pumpTable(tester);
      await caretIn(tester, state, table.children.first);

      final bounds = tester.getRect(find.byType(RichTextEditor));

      for (final grip in [_rowGrip, _columnGrip]) {
        final rect = tester.getRect(find.byIcon(grip));

        expect(bounds.contains(rect.topLeft), isTrue, reason: '$grip');
        expect(bounds.contains(rect.bottomRight), isTrue, reason: '$grip');
      }
    });
  });

  group('the handle a row or a column is taken by', () {
    /// Hovering a cell is what reveals them — the package shows a handle only
    /// while the pointer is over the row or the column it belongs to.
    Future<(Node, TestGesture)> hover(WidgetTester tester) async {
      final table = tableOf();
      final state = EditorState(
        document: Document.blank()..insert([0], [table]),
      );
      state.disableSealTimer = true;
      addTearDown(state.dispose);

      await tester.pumpWidget(
        _themed(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
                toolbar: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);

      await pointer.moveTo(
        tester.getCenter(find.text('Test', findRichText: true)),
      );
      await tester.pump();
      await tester.pump();

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });

      return (table, pointer);
    }

    testWidgets('is the grip the page hands a block by', (tester) async {
      await hover(tester);

      expect(find.byIcon(_rowGrip), findsOneWidget);
      expect(find.byIcon(_columnGrip), findsOneWidget);
    });

    /// The chip a grip is drawn on, which is what has to stay inside the table.
    Rect chipOf(WidgetTester tester, IconData grip) => tester.getRect(
      find
          .ancestor(of: find.byIcon(grip), matching: find.byType(DecoratedBox))
          .first,
    );

    testWidgets('never reaches outside the table', (tester) async {
      // Not a matter of taste: nothing answers the pointer beyond the box it is
      // drawn in, so a handle hanging in the margin is paint and nothing more —
      // reaching for it left the row, and the row leaving took it away.
      final (table, _) = await hover(tester);
      final cell = tester.getRect(find.byKey(table.children.first.key));
      final row = chipOf(tester, _rowGrip);
      final column = chipOf(tester, _columnGrip);

      // Each starts on the outer edge of the rule it sits on, and goes no
      // further out than that.
      expect(row.left, cell.left - TableDefaults.borderWidth);
      expect(column.top, cell.top - TableDefaults.borderWidth);
      expect(row.top, greaterThanOrEqualTo(cell.top));
      expect(row.bottom, lessThanOrEqualTo(cell.bottom));
      expect(column.left, greaterThanOrEqualTo(cell.left));
      expect(column.right, lessThanOrEqualTo(cell.right));
    });

    testWidgets('is padded by the width of the rule it sits on', (
      tester,
    ) async {
      // Every measurement it has comes off the table's own line, so it reads as
      // part of the table rather than as something dropped on it — and it stays
      // small, which is what it costs a cell in first characters.
      final (table, _) = await hover(tester);
      final cell = tester.getRect(find.byKey(table.children.first.key));

      for (final grip in [_rowGrip, _columnGrip]) {
        final chip = chipOf(tester, grip);
        final glyph = tester.getRect(find.byIcon(grip));

        expect(chip.width - glyph.width, 2 * TableDefaults.borderWidth);
        expect(chip.height - glyph.height, 2 * TableDefaults.borderWidth);
      }

      expect(
        chipOf(tester, Icons.drag_indicator).width,
        lessThan(cell.width / 8),
      );
    });

    testWidgets('stands in the middle of the row it takes', (tester) async {
      // The package works a row's height out as what its cell holds plus eight,
      // flat. Padded by anything else, the row and the handle standing against
      // it disagreed on where its middle was, and the grip sat towards the top.
      final (table, _) = await hover(tester);
      final cell = table.children.first;

      expect(
        tester.getRect(find.byIcon(_rowGrip)).center.dy,
        tester.getRect(find.byKey(cell.key)).center.dy,
      );
    });

    testWidgets('answers over all of what is drawn, and nothing more', (
      tester,
    ) async {
      // The package wraps whatever it is handed in an opaque mouse region of
      // its own. Anything reaching past the grip therefore takes the pointer
      // from the cells under it — and a row whose cell never sees the pointer
      // never shows its handle at all.
      final (_, _) = await hover(tester);
      final grip = chipOf(tester, _rowGrip);
      final target = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(_rowGrip),
              matching: find.byType(GestureDetector),
            )
            .first,
      );

      expect(target, grip);
    });

    testWidgets('stays there once the pointer reaches it', (tester) async {
      // It stands against the edge of the row it belongs to, and it is that row
      // being hovered which puts it there. Absorbing the pointer read as having left
      // the row: the handle took itself away from under the hand reaching for
      // it, every time.
      final (_, pointer) = await hover(tester);
      final grip = tester.getRect(find.byIcon(_rowGrip));

      // Onto the handle, which means off the row that revealed it.
      await pointer.moveTo(grip.centerLeft + const Offset(2, 0));
      await tester.pump();

      expect(find.byIcon(_rowGrip), findsOneWidget);
    });

    testWidgets('opens our menu, in the language the reader chose', (
      tester,
    ) async {
      // The package's is six untranslated entries in a card wide enough to
      // cover the table it acts on.
      await hover(tester);
      await tester.tap(find.byIcon(_columnGrip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(t('Insert a column before')), findsOneWidget);
      expect(find.text(t('Delete the column')), findsOneWidget);
      // What the package's own menu reads, which nothing translates.
      expect(find.text('Add before'), findsNothing);
    });

    testWidgets('and acts on the column it stands over', (tester) async {
      await hover(tester);
      await tester.tap(find.byIcon(_columnGrip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(t('Insert a column after')));
      await tester.pump();

      final table = find.byType(RichTextEditor).evaluate().isEmpty
          ? null
          : (tester.widget<RichTextEditor>(find.byType(RichTextEditor)))
                .editorState
                .document
                .root
                .children
                .single;

      expect(table?.attributes[TableBlockKeys.colsLen], 3);
    });
  });

  group('the caret at a table', () {
    /// A table between two paragraphs, mounted so the blocks around it have a
    /// selectable of its own — which is what a step lands on.
    Future<(EditorState, Node)> pumpAround(
      WidgetTester tester, {
      required List<Node> after,
    }) async {
      final table = tableOf();
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [paragraphNode(delta: Delta()..insert('Avant')), table, ...after],
          ),
      );
      state.disableSealTimer = true;
      addTearDown(state.dispose);

      await tester.pumpWidget(
        _themed(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
                toolbar: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });

      return (state, table);
    }

    testWidgets('steps back into the words before it rather than throwing', (
      tester,
    ) async {
      // The report that made this a test: the caret reaching the table and
      // cmd+arrow left throwing UnimplementedError into the console on every
      // press. The package goes to the start of a line by walking the block's
      // delta, and a table — selected whole, like a picture — has none.
      final (state, _) = await pumpAround(tester, after: []);
      state.selection = Selection.collapsed(Position(path: [1], offset: 0));

      expect(stepToLineStartCommand.handler(state), KeyEventResult.handled);
      expect(
        state.selection,
        Selection.collapsed(Position(path: [0], offset: 5)),
      );
    });

    testWidgets('and on into the words beyond it', (tester) async {
      final (state, _) = await pumpAround(
        tester,
        after: [paragraphNode(delta: Delta()..insert('Après'))],
      );
      state.selection = Selection.collapsed(Position(path: [1], offset: 1));

      expect(stepToLineEndCommand.handler(state), KeyEventResult.handled);
      expect(
        state.selection,
        Selection.collapsed(Position(path: [2], offset: 0)),
      );
    });

    testWidgets('does what the package on its own cannot', (tester) async {
      final (state, _) = await pumpAround(tester, after: []);
      state.selection = Selection.collapsed(Position(path: [1], offset: 0));

      // Left to the package, the very same press is the error in the console.
      expect(
        () => moveCursorToEndCommand.handler(state),
        throwsUnimplementedError,
      );
    });

    testWidgets('leaves a caret in the text to the package', (tester) async {
      final (state, _) = await pumpAround(tester, after: []);
      state.selection = Selection.collapsed(Position(path: [0], offset: 2));

      // Taking the key here would break the movement the package gets right.
      expect(stepToLineStartCommand.handler(state), KeyEventResult.ignored);
      expect(stepToLineEndCommand.handler(state), KeyEventResult.ignored);
    });

    testWidgets('deletes the empty line left under the table', (tester) async {
      // Backspace takes a line into the one above by merging their text, and a
      // table holds none — so the package gave up and the line under a table
      // could not be deleted by any means.
      final (state, table) = await pumpAround(tester, after: [paragraphNode()]);
      state.selection = Selection.collapsed(Position(path: [2], offset: 0));

      expect(deleteEmptyBlockCommand.handler(state), KeyEventResult.handled);
      await tester.pump();

      expect(state.document.root.children.map((block) => block.type), [
        'paragraph',
        TableBlockKeys.type,
      ]);
      // Back into the table rather than nowhere: the last cell it holds.
      expect(
        state.selection?.start.path,
        table.children.last.children.first.path,
      );
    });

    testWidgets('and leaves a line with something in it to the package', (
      tester,
    ) async {
      final (state, _) = await pumpAround(
        tester,
        after: [paragraphNode(delta: Delta()..insert('Après'))],
      );
      state.selection = Selection.collapsed(Position(path: [2], offset: 0));

      expect(deleteEmptyBlockCommand.handler(state), KeyEventResult.ignored);
      expect(state.document.root.children, hasLength(3));
    });
  });

  testWidgets('stands where the blocks around it stand', (tester) async {
    // The package insets its table by ten pixels, inside the widget and
    // reachable by nothing: it stood that much right of every paragraph.
    Future<double> leftOf(RichTextFeatures features) async {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [paragraphNode(delta: Delta()..insert('Avant')), tableOf()],
          ),
      );
      state.disableSealTimer = true;

      await tester.pumpWidget(
        _themed(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                editorState: state,
                features: features,
                toolbar: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final left = tester.getTopLeft(find.text('Test', findRichText: true)).dx;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      state.dispose();

      return left;
    }

    final ours = await leftOf(defaultRichTextFeatures);
    final theirs = await leftOf(
      defaultRichTextFeatures.without<TableFeature>(),
    );

    expect(theirs - ours, 10);
  });

  group('through markdown', () {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

    /// Columns of rows, the way the package builds one.
    Node tableOf(List<List<String>> columns) => TableNode.fromList([
      for (final column in columns)
        [
          for (final cell in column)
            paragraphNode(delta: Delta()..insert(cell)),
        ],
    ]).node;

    Document documentOf(List<Node> nodes) =>
        Document.blank()..insert([0], nodes);

    /// What each cell of the table reads as, once written and read back.
    List<String?> roundTrip(Node table) {
      final blocks = codec
          .decode(codec.encode(documentOf([table])))
          .root
          .children;

      expect(blocks.map((block) => block.type), [TableBlockKeys.type]);

      return [
        for (final cell in blocks.single.children)
          cell.children.first.delta?.toPlainText(),
      ];
    }

    test('a line break in a cell stays in that cell', () {
      // A row is a line: written as it stood, the break cut the row in two, the
      // halves read as nothing in particular, and the whole table was lost —
      // its markdown left in the page as the pipes it was made of.
      expect(
        roundTrip(
          tableOf([
            ['Test\nseconde ligne', 'c'],
            ['b', 'd'],
          ]),
        ),
        ['Test\nseconde ligne', 'c', 'b', 'd'],
      );
    });

    test('a pipe in a cell is the character it is, not a column', () {
      expect(
        roundTrip(
          tableOf([
            ['a|b', 'c'],
            ['b', 'd'],
          ]),
        ),
        ['a|b', 'c', 'b', 'd'],
      );
    });

    test('an empty cell comes back empty rather than holding a space', () {
      expect(
        roundTrip(
          tableOf([
            ['a', ''],
            ['', ''],
          ]),
        ),
        ['a', '', '', ''],
      );
    });

    test('a cell holding two blocks comes back as one, both lines kept', () {
      // Only the first is drawn — the package renders a cell's first child and
      // nothing else — so the second was invisible, and the encoder wrote the
      // two welded together.
      final table = tableOf([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      table.children.first.insert(
        paragraphNode(delta: Delta()..insert('suite')),
      );

      expect(roundTrip(table), ['a\nsuite', 'b', 'c', 'd']);
    });

    group('a column dragged wider', () {
      Node widened() {
        final table = tableOf([
          ['a', 'b'],
          ['c', 'd'],
        ]);

        for (final cell in table.children) {
          if (cell.attributes[TableCellBlockKeys.colPosition] == 0) {
            cell.updateAttributes({TableCellBlockKeys.width: 240.0});
          }
        }

        return table;
      }

      test('is carried in a marker of its own', () {
        // Markdown says nothing of how wide a column is drawn, so a resized
        // table came back at the default width on the next read.
        expect(
          codec.encode(documentOf([widened()])),
          '|a|c|\n|-|-|\n|b|d|\n<!-- cols:240,160 -->',
        );
      });

      test('comes back the width it was left', () {
        final blocks = codec
            .decode(codec.encode(documentOf([widened()])))
            .root
            .children;

        expect(blocks.map((block) => block.type), [TableBlockKeys.type]);
        expect(
          [
            for (final cell in blocks.single.children)
              cell.attributes[TableCellBlockKeys.width],
          ],
          [240.0, 240.0, 160.0, 160.0],
        );
      });

      test('and the marker never reaches the page as a block of its own', () {
        final document = codec.decode(
          '|a|c|\n|-|-|\n|b|d|\n<!-- cols:240,160 -->\n\nAprès',
        );

        expect(document.root.children.map((block) => block.type), [
          TableBlockKeys.type,
          ParagraphBlockKeys.type,
        ]);
      });

      test('leaves a table nobody resized writing no marker at all', () {
        expect(
          codec.encode(
            documentOf([
              tableOf([
                ['a', 'b'],
                ['c', 'd'],
              ]),
            ]),
          ),
          isNot(contains('<!--')),
        );
      });
    });
  });
}
