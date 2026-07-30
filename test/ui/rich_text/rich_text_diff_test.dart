/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Document documentOf(List<Node> nodes) => Document.blank()..insert([0], nodes);

  Node text(String value) => paragraphNode(delta: Delta()..insert(value));

  Node picture(int id, {double? width}) =>
      imageNode(url: 'attachment:$id', width: width);

  EditorState stateOf(List<Node> nodes) =>
      EditorState(document: documentOf(nodes));

  List<String> shapeOf(EditorState state) => [
    for (final node in state.document.root.children)
      node.type == ImageBlockKeys.type
          ? '${node.attributes[ImageBlockKeys.url]}'
          : node.delta?.toPlainText() ?? node.type,
  ];

  group('rich text diff', () {
    test('a document that says the same thing is not applied at all', () async {
      final state = stateOf([text('Intro'), picture(12), text('Outro')]);
      final blocks = [...state.document.root.children];

      expect(
        await applyRichTextDiff(
          state,
          documentOf([text('Intro'), picture(12), text('Outro')]),
        ),
        isFalse,
      );
      expect(state.document.root.children, blocks);
    });

    test(
      'a picture is left untouched when the text around it changes',
      () async {
        final state = stateOf([text('Intro'), picture(12), text('Outro')]);
        final image = state.document.root.children[1];
        final closing = state.document.root.children[2];

        await applyRichTextDiff(
          state,
          documentOf([text('Intro'), picture(12), text('Rewritten')]),
        );

        // Same node, so the same key, so the same element: the picture is never
        // rebuilt and never downloaded again.
        expect(identical(state.document.root.children[1], image), isTrue);
        // The paragraph is edited in place rather than swapped, which keeps the
        // caret standing in it.
        expect(identical(state.document.root.children[2], closing), isTrue);
        expect(shapeOf(state), ['Intro', 'attachment:12', 'Rewritten']);
      },
    );

    test('a picture resized elsewhere keeps its block', () async {
      final state = stateOf([picture(12, width: 720)]);
      final image = state.document.root.children.first;

      await applyRichTextDiff(state, documentOf([picture(12, width: 420)]));

      expect(identical(state.document.root.children.first, image), isTrue);
      expect(image.attributes[ImageBlockKeys.width], 420);
    });

    test('a size dropped from a picture is dropped from the block', () async {
      final state = stateOf([picture(12, width: 420)]);

      await applyRichTextDiff(state, documentOf([picture(12)]));

      expect(
        state.document.root.children.first.attributes[ImageBlockKeys.width],
        isNull,
      );
    });

    test(
      'a block inserted in the middle leaves its neighbours alone',
      () async {
        final state = stateOf([text('Intro'), picture(12), text('Outro')]);
        final blocks = [...state.document.root.children];

        await applyRichTextDiff(
          state,
          documentOf([
            text('Intro'),
            picture(12),
            text('Added'),
            text('Outro'),
          ]),
        );

        expect(shapeOf(state), ['Intro', 'attachment:12', 'Added', 'Outro']);
        expect(identical(state.document.root.children[0], blocks[0]), isTrue);
        expect(identical(state.document.root.children[1], blocks[1]), isTrue);
        expect(identical(state.document.root.children[3], blocks[2]), isTrue);
      },
    );

    test(
      'a block dropped from the middle leaves its neighbours alone',
      () async {
        final state = stateOf([text('Intro'), picture(12), text('Outro')]);
        final blocks = [...state.document.root.children];

        await applyRichTextDiff(
          state,
          documentOf([text('Intro'), text('Outro')]),
        );

        expect(shapeOf(state), ['Intro', 'Outro']);
        expect(identical(state.document.root.children[0], blocks[0]), isTrue);
        expect(identical(state.document.root.children[1], blocks[2]), isTrue);
      },
    );

    test(
      'two pictures keep their own blocks when one is removed between them',
      () async {
        final state = stateOf([picture(12), text('Between'), picture(13)]);
        final first = state.document.root.children[0];
        final second = state.document.root.children[2];

        await applyRichTextDiff(state, documentOf([picture(12), picture(13)]));

        expect(shapeOf(state), ['attachment:12', 'attachment:13']);
        expect(identical(state.document.root.children[0], first), isTrue);
        expect(identical(state.document.root.children[1], second), isTrue);
      },
    );

    test('several edits at once end on the document that arrived', () async {
      final state = stateOf([
        text('One'),
        text('Two'),
        picture(12),
        text('Three'),
        text('Four'),
      ]);

      await applyRichTextDiff(
        state,
        documentOf([
          text('One'),
          picture(12),
          text('Third'),
          text('Four'),
          text('Five'),
        ]),
      );

      expect(shapeOf(state), ['One', 'attachment:12', 'Third', 'Four', 'Five']);
    });

    test('ce qui arrive d\'ailleurs ne se défait pas', () async {
      // Charger une note, ou recevoir la description que le serveur a réécrite
      // en sauvant, n'est pas une frappe : le bouton annuler doit rester mort.
      final state = stateOf([text('Avant')]);

      await applyRichTextDiff(state, documentOf([text('Après')]));

      expect(state.undoManager.undoStack.isEmpty, isTrue);
      expect(shapeOf(state), ['Après']);
    });

    test('a nested block only touches the child that changed', () async {
      final state = stateOf([
        bulletedListNode(
          delta: Delta()..insert('Parent'),
          children: [text('Kept'), text('Moved')],
        ),
      ]);
      final parent = state.document.root.children.first;
      final kept = parent.children.first;

      await applyRichTextDiff(
        state,
        documentOf([
          bulletedListNode(
            delta: Delta()..insert('Parent'),
            children: [text('Kept'), text('Rewritten')],
          ),
        ]),
      );

      expect(identical(state.document.root.children.first, parent), isTrue);
      expect(identical(parent.children.first, kept), isTrue);
      expect(parent.children[1].delta?.toPlainText(), 'Rewritten');
    });

    test('an emptied document keeps nothing of the old one', () async {
      final state = stateOf([text('Intro'), picture(12)]);

      await applyRichTextDiff(state, documentOf([text('')]));

      expect(shapeOf(state), ['']);
    });

    test('a caret left standing in a block that is gone is dropped', () async {
      final state = stateOf([text('Intro'), text('Doomed')]);

      await applyRichTextDiff(state, documentOf([text('Intro')]));

      expect(state.selection, isNull);
    });

    group('what someone is writing', () {
      test('is not rewritten by a version that arrives', () async {
        final state = stateOf([text('Intro'), text('Typing here')]);
        state.selection = Selection.collapsed(Position(path: [1], offset: 6));

        await applyRichTextDiff(
          state,
          documentOf([text('Intro'), text('Something else')]),
        );

        expect(shapeOf(state), ['Intro', 'Typing here']);
      });

      test('is not swapped for another kind of block', () async {
        // The report that made this a test: '#' typed to mention a flow, saved
        // as markdown, read back as an empty heading. The diff applied that
        // faithfully, the trigger vanished from under the machine watching it,
        // and the suggestion list closed the moment the autosave ran.
        final state = stateOf([text('#')]);
        state.selection = Selection.collapsed(Position(path: [0], offset: 1));

        await applyRichTextDiff(
          state,
          documentOf([headingNode(level: 1, delta: Delta())]),
        );

        expect(
          state.document.root.children.single.type,
          ParagraphBlockKeys.type,
        );
        expect(shapeOf(state), ['#']);
      });

      test('is not deleted along with the block holding it', () async {
        final state = stateOf([
          paragraphNode(
            delta: Delta()..insert('Parent'),
            children: [text('Typing here')],
          ),
        ]);
        state.selection = Selection.collapsed(
          Position(path: [0, 0], offset: 6),
        );

        await applyRichTextDiff(state, documentOf([text('Replaced')]));

        expect(shapeOf(state), ['Parent']);
        expect(
          state.document.root.children.single.children.single.delta
              ?.toPlainText(),
          'Typing here',
        );
      });

      test('holds up nothing else in the document', () async {
        final state = stateOf([
          text('Intro'),
          text('Typing here'),
          text('Outro'),
        ]);
        state.selection = Selection.collapsed(Position(path: [1], offset: 6));

        await applyRichTextDiff(
          state,
          documentOf([
            text('Rewritten'),
            text('Something else'),
            text('Also rewritten'),
          ]),
        );

        // Only the block under the caret waits; the rest arrives.
        expect(shapeOf(state), ['Rewritten', 'Typing here', 'Also rewritten']);
      });

      test('is nothing at all when the caret is elsewhere', () async {
        final state = stateOf([text('Intro'), text('Was here')]);
        state.selection = Selection.collapsed(Position(path: [0], offset: 2));

        await applyRichTextDiff(
          state,
          documentOf([text('Intro'), text('Rewritten')]),
        );

        expect(shapeOf(state), ['Intro', 'Rewritten']);
      });
    });

    test(
      'a caret in an untouched block survives a change made above it',
      () async {
        final state = stateOf([text('Intro'), text('Typing here')]);
        state.selection = Selection.collapsed(Position(path: [1], offset: 6));

        await applyRichTextDiff(
          state,
          documentOf([text('Intro'), text('Added'), text('Typing here')]),
        );

        expect(
          state.selection,
          Selection.collapsed(Position(path: [2], offset: 6)),
        );
      },
    );

    group('a table', () {
      /// Columns of rows, the way the package builds one, [measured] carrying
      /// the sizes it writes back into its own cells once it has laid out.
      Node table(List<List<String>> columns, {double? measured}) {
        final node = TableNode.fromList([
          for (final column in columns) [for (final cell in column) text(cell)],
        ]).node;

        for (final cell in node.children) {
          if (measured != null) {
            cell.updateAttributes({TableCellBlockKeys.height: measured});
          }
        }

        return node;
      }

      bool draws(Node node) => TableBlockComponentBuilder().validate(node);

      test(
        'is left strictly alone when only the sizes it measured differ',
        () async {
          // Markdown carries no sizes, so what comes back from the server never
          // has them: compared as they stand, an untouched table differed from
          // itself on every save and was rebuilt for nothing.
          final state = stateOf([
            text('Intro'),
            table([
              ['A', 'B'],
              ['C', 'D'],
            ], measured: 30),
          ]);
          final before = state.document.root.children[1];

          expect(
            await applyRichTextDiff(
              state,
              documentOf([
                text('Intro'),
                table([
                  ['A', 'B'],
                  ['C', 'D'],
                ]),
              ]),
            ),
            isFalse,
          );
          expect(identical(state.document.root.children[1], before), isTrue);
        },
      );

      test('changed shape is replaced whole, and still draws', () async {
        final state = stateOf([
          table([
            ['A', 'B'],
            ['C', 'D'],
          ], measured: 30),
        ]);
        final before = state.document.root.children.single;

        await applyRichTextDiff(
          state,
          documentOf([
            table([
              ['A', 'B'],
            ]),
          ]),
        );

        final after = state.document.root.children.single;

        // A new block, not the old one patched: the counts on the table and
        // the cells under it can only be brought over together.
        expect(identical(after, before), isFalse);
        expect(after.attributes[TableBlockKeys.colsLen], 1);
        expect(after.children, hasLength(2));
        expect(draws(after), isTrue);
      });

      test('is not patched cell by cell under the caret', () async {
        // The report that made this a test: a column added, the autosave
        // running with the caret still in a cell, and an earlier version
        // arriving. Its cells were deleted one by one while the counts on the
        // block itself — under the caret, so left alone — went on saying nine.
        // A table saying nine over six cells is one the editor cannot draw at
        // all: it renders the package's bare "placeholder" in its place, and
        // the text goes with it.
        final state = stateOf([
          table([
            ['A', 'B'],
            ['C', 'D'],
            ['E', 'F'],
          ], measured: 30),
        ]);
        state.selection = Selection.collapsed(
          Position(path: [0, 0, 0], offset: 0),
        );

        await applyRichTextDiff(
          state,
          documentOf([
            table([
              ['A', 'B'],
              ['C', 'D'],
            ]),
          ]),
        );

        final after = state.document.root.children.single;

        // Untouched, as any block being written is — the typist's own save is
        // what brings the two back in step.
        expect(after.children, hasLength(6));
        expect(draws(after), isTrue);
      });
    });

    test('a read-only view still takes the content that arrives', () async {
      final state = stateOf([text('Before')])..editable = false;

      expect(
        await applyRichTextDiff(state, documentOf([text('After')])),
        isTrue,
      );
      expect(shapeOf(state), ['After']);
      expect(state.editable, isFalse);
    });
  });
}
