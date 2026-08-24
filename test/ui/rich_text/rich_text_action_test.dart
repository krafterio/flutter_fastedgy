/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RichTextAction actionOf(String id) =>
      RichTextActions.standard.firstWhere((action) => action.id == id);

  EditorState stateOf(String text) {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
    );
    state.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: text.length,
    );

    return state;
  }

  group('ce que fait une action', () {
    test('une marque se pose et se retire', () async {
      final state = stateOf('Lait');
      final bold = actionOf('bold');

      expect(bold.isActive(state), isFalse);

      await bold.run(state);
      expect(bold.isActive(state), isTrue);

      await bold.run(state);
      expect(bold.isActive(state), isFalse);

      state.dispose();
    });

    test('un type de bloc s\'applique et revient au paragraphe', () async {
      final state = stateOf('Pain');
      final list = actionOf('bulleted_list');

      await list.run(state);
      expect(state.getNodeAtPath([0])?.type, BulletedListBlockKeys.type);
      expect(list.isActive(state), isTrue);

      await list.run(state);
      expect(state.getNodeAtPath([0])?.type, ParagraphBlockKeys.type);

      state.dispose();
    });

    test('un paragraphe multiligne donne une puce par ligne', () async {
      // Un retour seul en markdown est un saut de ligne, pas un paragraphe.
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [
              paragraphNode(
                delta: Delta()
                  ..insert('un\nde')
                  ..insert('ux', attributes: {'bold': true})
                  ..insert('\ntrois'),
              ),
            ],
          ),
      );
      state.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 13,
      );

      await actionOf('bulleted_list').run(state);

      final blocks = state.document.root.children;

      expect(blocks, hasLength(3));
      expect(
        blocks.every((node) => node.type == BulletedListBlockKeys.type),
        isTrue,
      );
      expect(blocks.map((node) => node.delta?.toPlainText()), [
        'un',
        'deux',
        'trois',
      ]);
      expect(blocks[1].delta?.toJson(), [
        {'insert': 'de'},
        {
          'insert': 'ux',
          'attributes': {'bold': true},
        },
      ]);
      expect(state.selection?.end.path, [2]);
      expect(state.selection?.end.offset, 5);

      state.dispose();
    });

    test('le texte du bloc survit au changement de type', () async {
      final state = stateOf('Œufs');

      await actionOf('quote').run(state);

      expect(state.getNodeAtPath([0])?.delta?.toPlainText(), 'Œufs');

      state.dispose();
    });

    test(
      'un titre change de niveau, plutôt que de redevenir un paragraphe',
      () async {
        final state = stateOf('Titre');
        final h1 = actionOf('heading_1');
        final h2 = actionOf('heading_2');

        await h2.run(state);

        expect(state.getNodeAtPath([0])?.attributes[HeadingBlockKeys.level], 2);
        expect(h2.isActive(state), isTrue);
        expect(h1.isActive(state), isFalse);

        await h1.run(state);

        expect(state.getNodeAtPath([0])?.type, HeadingBlockKeys.type);
        expect(state.getNodeAtPath([0])?.attributes[HeadingBlockKeys.level], 1);

        await actionOf('heading_3').run(state);

        expect(state.getNodeAtPath([0])?.attributes[HeadingBlockKeys.level], 3);
        expect(h1.isActive(state), isFalse);

        await h1.run(state);

        // Et le sien le ramène, comme n'importe quel bouton de bloc.
        await h1.run(state);

        expect(state.getNodeAtPath([0])?.type, ParagraphBlockKeys.type);

        state.dispose();
      },
    );

    test('une case cochée reste une case à cocher', () async {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [todoListNode(checked: true, delta: Delta()..insert('Courses'))],
          ),
      );
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));

      final todo = actionOf('todo_list');

      // `checked: false` est ce avec quoi on en crée une, pas ce qui en fait
      // une : le bouton ne s'allumait que sur les non cochées, et cochait
      // celles qui l'étaient au lieu de sortir de la liste.
      expect(todo.isActive(state), isTrue);

      await todo.run(state);

      expect(state.getNodeAtPath([0])?.type, ParagraphBlockKeys.type);

      state.dispose();
    });

    test('une action à cocher porte son attribut', () async {
      final state = stateOf('Courses');

      await actionOf('todo_list').run(state);

      final node = state.getNodeAtPath([0]);

      expect(node?.type, TodoListBlockKeys.type);
      expect(node?.attributes[TodoListBlockKeys.checked], isFalse);

      state.dispose();
    });

    test(
      'revenir en arrière n\'est offert qu\'une fois qu\'il y a de quoi',
      () async {
        final state = stateOf('Rien');
        final undo = actionOf('undo');

        expect(undo.isEnabled(state), isFalse);

        await actionOf('bold').run(state);

        expect(undo.isEnabled(state), isTrue);

        state.dispose();
      },
    );

    test('le jeu standard est groupé, pas en vrac', () {
      final groups = RichTextActions.standard.map((action) => action.group);

      expect(groups.toSet().length, greaterThan(1));
      expect(groups.toList(), orderedEquals(groups.toList()..sort()));
    });
  });

  group('ce qu\'une feature ajoute à la barre', () {
    test('image n\'est offert que là où la feature est montée', () {
      expect(
        const RichTextFeatures([ImageFeature()]).actions
            .map((action) => action.id),
        contains('image'),
      );
      expect(const RichTextFeatures([ParagraphFeature()]).actions, isEmpty);
    });

    testWidgets('et se range après la citation, avant la règle', (
      tester,
    ) async {
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(delta: Delta()..insert('Mars'))]),
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

      state.selection = Selection.collapsed(Position(path: [0], offset: 4));
      await tester.pumpAndSettle();

      double xOf(FastEdgyGlyph glyph) =>
          tester.getTopLeft(find.byIcon(FastEdgyIcons.material[glyph])).dx;

      expect(xOf(FastEdgyGlyph.quote), lessThan(xOf(FastEdgyGlyph.image)));
      expect(xOf(FastEdgyGlyph.image), lessThan(xOf(FastEdgyGlyph.rule)));
    });
  });

  group('ce que dessine la barre', () {
    Future<void> pump(WidgetTester tester, EditorState state) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RichTextActionBar(
                editorState: state,
                actions: RichTextActions.marks,
              ),
            ),
          ),
        );

    testWidgets('un bouton par action', (tester) async {
      final state = stateOf('Texte');
      addTearDown(state.dispose);

      await pump(tester, state);

      expect(find.byType(Icon), findsNWidgets(RichTextActions.marks.length));
    });

    testWidgets('taper un bouton applique son action', (tester) async {
      final state = stateOf('Texte');
      addTearDown(state.dispose);

      await pump(tester, state);
      await tester.tap(find.byType(Icon).first);
      await tester.pumpAndSettle();

      expect(actionOf('bold').isActive(state), isTrue);
    });
  });
}
