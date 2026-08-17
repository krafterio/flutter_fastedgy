/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  /// Records every query it was asked, and answers what it was told to.
  final asked = <String>[];
  final heard = <MentionOptions>[];
  var answers = <MentionCandidate>[];

  MentionSource sourceOf(
    String trigger, {
    String model = 'record',
    int priority = 0,
  }) => MentionSource(
    trigger: trigger,
    model: model,
    getLabel: () => 'Flow',
    icon: Icons.tag,
    priority: priority,
    search: (query, options) async {
      asked.add(query);
      heard.add(options);

      return answers;
    },
  );

  setUp(() {
    asked.clear();
    heard.clear();
    answers = [
      const MentionCandidate(
        id: 42,
        label: 'REF-42',
        subtitle: 'Première étape',
      ),
      const MentionCandidate(id: 43, label: 'REF-43'),
    ];
  });

  EditorState stateOf(String text) {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert(text))]),
    );
    addTearDown(state.dispose);

    return state;
  }

  Node blockOf(EditorState state) => state.document.root.children.first;

  String textOf(EditorState state) => blockOf(state).delta!.toPlainText();

  void caretAt(EditorState state, int offset) => state.selection =
      Selection.collapsed(Position(path: [0], offset: offset));

  /// Arms [feature] by typing the last character of the trigger where the caret
  /// stands, exactly as the editor's character shortcut does.
  Future<bool> type(
    MentionFeature feature,
    EditorState state,
    String character,
  ) async {
    final event = feature.characterShortcuts.firstWhere(
      (e) => e.character == character,
    );

    return event.handler(state);
  }

  group('what arms a mention', () {
    final controller = MentionController(
      MentionSources([
        sourceOf('@', model: 'user'),
        sourceOf('::'),
        sourceOf(':'),
      ]),
    );

    test('a trigger at the start of a line, or after a space or a bracket', () {
      expect(controller.sourceFor('@', '')?.model, 'user');
      expect(controller.sourceFor('@', 'Bonjour ')?.model, 'user');
      expect(controller.sourceFor('@', 'Bonjour (')?.model, 'user');
      expect(controller.sourceFor('@', 'Bonjour "')?.model, 'user');
    });

    test('never inside a word — an address is not a mention', () {
      expect(controller.sourceFor('@', 'francois'), isNull);
      expect(controller.sourceFor('@', 'a.b'), isNull);
    });

    test(
      'the longest trigger wins, so a doubled one is not read as a single',
      () {
        // Why Odoo moved its canned responses from ':' to '::': a single
        // character that reads as punctuation collides with what people type.
        expect(controller.sourceFor(':', '')?.trigger, ':');
        expect(controller.sourceFor(':', ':')?.trigger, '::');
      },
    );
  });

  group('typing a trigger', () {
    test('arms the machine and leaves the character in the text', () async {
      final feature = MentionFeature(sources: MentionSources([sourceOf('#')]));
      final state = stateOf('Voir ');
      caretAt(state, 5);

      expect(await type(feature, state, '#'), isTrue);
      expect(textOf(state), 'Voir #');
      expect(feature.controllerOf(state).isOpen, isTrue);
      expect(feature.controllerOf(state).query, '');
    });

    test(
      'declines the character mid-word, which stays a plain character',
      () async {
        final feature = MentionFeature(
          sources: MentionSources([sourceOf('#')]),
        );
        final state = stateOf('abc');
        caretAt(state, 3);

        // Declined, so the editor inserts it itself — nothing is written here.
        expect(await type(feature, state, '#'), isFalse);
        expect(textOf(state), 'abc');
        expect(feature.controllerOf(state).isOpen, isFalse);
      },
    );
  });

  group('the query', () {
    late MentionFeature feature;
    late EditorState state;

    setUp(() async {
      feature = MentionFeature(sources: MentionSources([sourceOf('#')]));
      state = stateOf('');
      caretAt(state, 0);
      await type(feature, state, '#');
    });

    Future<void> write(String text) async {
      final node = blockOf(state);
      final at = node.delta!.length;

      await state.apply(state.transaction..insertText(node, at, text));
    }

    test('grows with what is typed, spaces included', () async {
      await write('Deuxième version');

      expect(feature.controllerOf(state).query, 'Deuxième version');
      expect(feature.controllerOf(state).isOpen, isTrue);
    });

    test(
      'reaches the source behind a debounce, once per settled query',
      () async {
        await write('KAS');
        await Future<void>.delayed(const Duration(milliseconds: 260));

        expect(asked, ['KAS']);
        expect(feature.controllerOf(state).candidates, hasLength(2));
      },
    );

    test('carries what the document says to the source', () async {
      await write('KAS');
      await Future<void>.delayed(const Duration(milliseconds: 260));

      // The standard set says nothing, so a source reads its own defaults.
      expect(heard, [MentionOptions.none]);
    });

    test('closes when the trigger itself is deleted', () async {
      await write('KAS');
      final node = blockOf(state);

      await state.apply(state.transaction..deleteText(node, 0, 1));

      expect(feature.controllerOf(state).isOpen, isFalse);
    });

    test('closes when the caret leaves for another block', () async {
      await state.apply(
        state.transaction
          ..insertNode([1], paragraphNode(delta: Delta()..insert('Ailleurs'))),
      );
      state.selection = Selection.collapsed(Position(path: [1], offset: 3));

      expect(feature.controllerOf(state).isOpen, isFalse);
    });

    test(
      'gives up once the query runs into a new word with nothing to offer',
      () async {
        // What ends the hunt when spaces are allowed: the trigger turns out to
        // have been ordinary punctuation.
        answers = [];
        await write('rien du tout ');
        await Future<void>.delayed(const Duration(milliseconds: 260));

        expect(feature.controllerOf(state).isOpen, isFalse);
        expect(textOf(state), '#rien du tout ');
      },
    );
  });

  group('choosing a suggestion', () {
    late MentionFeature feature;
    late EditorState state;

    setUp(() async {
      feature = MentionFeature(sources: MentionSources([sourceOf('#')]));
      state = stateOf('Voir ');
      caretAt(state, 5);
      await type(feature, state, '#');
      await state.apply(
        state.transaction..insertText(blockOf(state), 6, 'KAS'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));
    });

    test('the arrows walk the list and wrap around it', () {
      expect(feature.controllerOf(state).highlighted, 0);
      expect(feature.controllerOf(state).moveHighlight(1), isTrue);
      expect(feature.controllerOf(state).highlighted, 1);
      // Two candidates, so one more step is back to the first.
      feature.controllerOf(state).moveHighlight(1);
      expect(feature.controllerOf(state).highlighted, 0);
      feature.controllerOf(state).moveHighlight(-1);
      expect(feature.controllerOf(state).highlighted, 1);
    });

    test('enter writes one character carrying the record it names', () async {
      final enter = feature.characterShortcuts.firstWhere(
        (e) => e.character == '\n',
      );

      expect(await enter.handler(state), isTrue);
      expect(feature.controllerOf(state).isOpen, isFalse);

      // One character wide, whatever it is drawn as: there is no inside for the
      // caret to land in, and one backspace takes the whole thing.
      expect(textOf(state), 'Voir \u{FFFC} ');

      final operations = blockOf(state).delta!.toList();
      final mention = mentionOf(operations[1] as TextInsert)!;

      expect(mention.label, '#REF-42');
      // The address names the record, so the mention survives the flow moving
      // to another project.
      expect(mention.address.uri.toString(), '/r/record/42');
      // Somewhere to put the caret, and something to type on.
      expect((operations.last as TextInsert).text, ' ');
      expect(mentionOf(operations.last as TextInsert), isNull);
    });

    test('enter with nothing to offer is left to the editor', () async {
      feature.controllerOf(state).close();
      final enter = feature.characterShortcuts.firstWhere(
        (e) => e.character == '\n',
      );

      expect(await enter.handler(state), isFalse);
    });

    test('escape gives up and leaves the text exactly as typed', () {
      final escape = feature.commandShortcuts.firstWhere(
        (e) => e.key == 'mention close',
      );

      expect(escape.handler(state), KeyEventResult.handled);
      expect(feature.controllerOf(state).isOpen, isFalse);
      expect(textOf(state), 'Voir #KAS');
      // Closed, so the key goes back to the editor's own handling of it.
      expect(escape.handler(state), KeyEventResult.ignored);
    });
  });

  group('the registry', () {
    test('ranks by priority, and keeps the registration order on a tie', () {
      final sources = MentionSources([
        sourceOf('#'),
        sourceOf('%', priority: 300),
        sourceOf(r'$'),
      ]);

      expect(sources.ordered.map((source) => source.trigger), ['%', '#', r'$']);
    });

    test('arms on the longest trigger first, whatever the priorities say', () {
      // A priority orders a menu; it must never decide which trigger fires, or
      // a '::' outranked by ':' could never arm at all.
      final sources = MentionSources([
        sourceOf(':', priority: 900),
        sourceOf('::'),
      ]);

      expect(sources.armingOrder.first.trigger, '::');
    });

    test('takes what the app registers, one source at a time', () {
      final sources = MentionSources()..register(sourceOf('#'));

      expect(sources.isEmpty, isFalse);
      expect(sources.all.single.trigger, '#');
      expect(sources.armingCharacters, {'#'});
    });
  });

  group('what a document tells its sources', () {
    const said = MentionOptions({
      MentionOption<bool>('test.flag', false): true,
    });

    Future<MentionFeature> hunting(MentionFeature feature) async {
      final state = stateOf('');
      caretAt(state, 0);
      await type(feature, state, '#');
      await state.apply(
        state.transaction..insertText(blockOf(state), 1, 'KAS'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));

      return feature;
    }

    test('reaches the source it offers', () async {
      await hunting(
        MentionFeature(sources: MentionSources([sourceOf('#')]), options: said),
      );

      expect(heard, [said]);
    });

    test(
      'is what a document says now, not what it said when it opened',
      () async {
        // The controller outlives the widget: it is keyed on the editor state,
        // which stays put while the document is handed new options.
        final sources = MentionSources([sourceOf('#')]);
        final state = stateOf('');
        caretAt(state, 0);

        MentionFeature(sources: sources).controllerOf(state);

        expect(
          MentionFeature(
            sources: sources,
            options: said,
          ).controllerOf(state).options,
          said,
        );
      },
    );
  });

  test('an app that registered nothing arms no trigger at all', () {
    const feature = MentionFeature();

    expect(feature.characterShortcuts, isEmpty);
    expect(feature.commandShortcuts, isEmpty);
    expect(feature.menuItems, isEmpty);
  });

  test('the "/" menu lists the sources by priority, not by registration', () {
    final feature = MentionFeature(
      sources: MentionSources([
        sourceOf('#'),
        sourceOf('%', model: 'project', priority: 300),
        sourceOf(r'$', model: 'note', priority: 100),
      ]),
    );

    expect(feature.menuItems, hasLength(3));
    expect(feature.menuItems.first.keywords, contains('%'));
    expect(feature.menuItems.last.keywords, contains('#'));
  });

  testWidgets('the list shows under the trigger and writes what is picked', (
    tester,
  ) async {
    final feature = MentionFeature(sources: MentionSources([sourceOf('#')]));
    final state = stateOf('Voir ');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: RichTextEditor(
              editorState: state,
              features: RichTextFeatures([feature]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    caretAt(state, 5);
    await type(feature, state, '#');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();

    expect(find.text('REF-42'), findsOneWidget);
    expect(find.text('Première étape'), findsOneWidget);

    await tester.tap(find.text('REF-43'));
    await tester.pumpAndSettle();

    expect(textOf(state), 'Voir \u{FFFC} ');
    // Drawn as a chip, so the label is on screen while the text holds one
    // character — and the list went with the mention it wrote.
    expect(find.text('#REF-43'), findsOneWidget);
    expect(find.text('REF-42'), findsNothing);
  });

  test('a query is not read as markdown while it is being written', () async {
    // The report that made this a test: '#' armed the flow trigger, the first
    // space of the query was taken as a heading, and the conversion deleted
    // the '#' — the machine found nothing where it was armed and gave up, so
    // the list vanished the moment anything was typed.
    final features = RichTextFeatures([
      const ParagraphFeature(),
      MentionFeature(sources: MentionSources([sourceOf('#')])),
    ]);
    final events = [
      ...features.characterShortcuts,
      ...standardCharacterShortcutEvents
          .where((event) => event != slashCommand)
          .map(features.guard),
    ];
    final state = stateOf('');
    caretAt(state, 0);

    // The space right after the trigger, which is what the heading answers to.
    for (final character in '# Deuxième version'.split('')) {
      // Every event registered for the character, in order, until one takes it
      // — exactly as the editor's own key handler does. Several answer to a
      // space, and the heading is not the first of them.
      var handled = false;

      for (final event in events.where(
        (event) => event.character == character,
      )) {
        if (handled = await event.handler(state)) {
          break;
        }
      }

      if (!handled) {
        await state.insertTextAtPosition(
          character,
          position: state.selection!.start,
        );
      }
    }

    expect(blockOf(state).type, ParagraphBlockKeys.type);
    expect(textOf(state), '# Deuxième version');
    expect(
      features.features
          .whereType<MentionFeature>()
          .single
          .controllerOf(state)
          .query,
      ' Deuxième version',
    );
  });

  test('typing an ordinary sentence still lands in the text', () async {
    // The report that made this a test: with the mentions in the standard set,
    // the editor took the keys and wrote nothing. Driven exactly as the editor
    // drives them — the feature's own shortcuts first, the package's behind.
    final features = RichTextFeatures([
      const ParagraphFeature(),
      MentionFeature(
        sources: MentionSources([sourceOf('@', model: 'user'), sourceOf('#')]),
      ),
    ]);
    final events = [
      ...features.characterShortcuts,
      ...standardCharacterShortcutEvents
          .where((event) => event != slashCommand)
          .map(features.guard),
    ];
    final state = stateOf('');
    caretAt(state, 0);

    for (final character in 'Bonjour, 100% fait.'.split('')) {
      final event = events
          .where((event) => event.character == character)
          .firstOrNull;

      if (event != null && await event.handler(state)) {
        continue;
      }

      await state.insertTextAtPosition(
        character,
        position: state.selection!.start,
      );
    }

    expect(textOf(state), 'Bonjour, 100% fait.');
    // The percent sat inside a number, so it armed nothing.
    expect(state.selection!.end.offset, 19);
  });
}
