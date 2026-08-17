/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show container;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

final _address = MentionAddress(
  model: 'record',
  id: 42,
  uri: Uri.parse('/r/record/42'),
);
final _mention = Mention(address: _address, label: '#REF-42');

/// A decorator that only marks the run it was handed, so the chain can be read
/// off the result.
class _Marker extends RichTextFeature {
  const _Marker(this.mark);

  final String mark;

  @override
  TextSpanDecoratorForAttribute? get textSpanDecorator =>
      (context, node, index, text, before, after) =>
          TextSpan(text: '${before.text ?? ''}$mark');
}

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  Document documentOf(Delta delta) =>
      Document.blank()..insert([0], [paragraphNode(delta: delta)]);

  /// A sentence holding one mention, as the editor keeps it.
  Document sentence() => documentOf(
    Delta()
      ..insert('Voir ')
      ..addAll(mentionRun(_mention))
      ..insert(' demain'),
  );

  List<TextInsert> runsOf(Document document) => [
    for (final operation in document.root.children.first.delta!.toList())
      operation as TextInsert,
  ];

  group('what a mention is', () {
    test('one character wide, whatever it is drawn as', () {
      final runs = runsOf(sentence());

      // No inside for the caret to land in, and one backspace takes the whole
      // thing — which is only true because it is one character.
      expect(runs[1].text, '\u{FFFC}');
      expect(runs[1].text.length, 1);
      expect(mentionOf(runs[1])?.label, '#REF-42');
      expect(mentionOf(runs[1])?.address, _address);
    });

    test('plain words are not one, and neither is a broken attribute', () {
      expect(mentionOf(TextInsert('Rien')), isNull);
      expect(
        mentionOf(TextInsert('X', attributes: {mentionAttribute: 'nonsense'})),
        isNull,
      );
      expect(
        mentionOf(
          TextInsert(
            'X',
            attributes: {
              mentionAttribute: {'address': 'nope', 'label': 'X'},
            },
          ),
        ),
        isNull,
      );
      // A view address says which screen, not which record: it is not what a
      // mention points at.
      expect(
        mentionOf(
          TextInsert(
            'X',
            attributes: {
              mentionAttribute: {'address': '/projects/18/flows', 'label': 'X'},
            },
          ),
        ),
        isNull,
      );
    });
  });

  group('the decorator chain', () {
    /// A context out of a real tree: what is under test reads nothing from it,
    /// but there is no making one up outside a pumped widget.
    Future<BuildContext> contextOf(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      return tester.element(find.byType(SizedBox));
    }

    testWidgets(
      'a mention is the one run drawn as a widget rather than as text',
      (tester) async {
        final span = mentionTextSpanDecorator(
          await contextOf(tester),
          Node(type: 'paragraph'),
          0,
          runsOf(sentence())[1],
          const TextSpan(),
          const TextSpan(),
        );

        // Which is what buys the padding and the rounded corners: a text style
        // background is a paint, and a paint has no shape.
        expect(span, isA<WidgetSpan>());
        expect((span as WidgetSpan).child, isA<MentionChip>());
      },
    );

    testWidgets(
      'anything else is left exactly as the features before it made it',
      (tester) async {
        const before = TextSpan(text: 'Voir');

        expect(
          mentionTextSpanDecorator(
            await contextOf(tester),
            Node(type: 'paragraph'),
            0,
            TextInsert('Voir'),
            before,
            const TextSpan(),
          ),
          same(before),
        );
      },
    );

    testWidgets(
      'runs every feature in order, each handed what the last one made',
      (tester) async {
        final decorate = const RichTextFeatures([
          _Marker('a'),
          _Marker('b'),
        ]).textSpanDecorator!;
        final span =
            decorate(
                  await contextOf(tester),
                  Node(type: 'paragraph'),
                  0,
                  TextInsert(''),
                  const TextSpan(text: ''),
                  const TextSpan(),
                )
                as TextSpan;

        expect(span.text, 'ab');
      },
    );

    test('is null when no feature has anything to say', () {
      expect(const RichTextFeatures([]).textSpanDecorator, isNull);
    });
  });

  group('through markdown', () {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

    test('a mention travels as the plain link anything can read', () {
      // Markdown has no inline objects, and the field is read by the agent and
      // by whatever else touches it.
      expect(
        codec.encode(sentence()).trim(),
        'Voir [#REF-42](/r/record/42) demain',
      );
    });

    test('and comes home an object again', () {
      final runs = runsOf(codec.decode(codec.encode(sentence())));

      expect(runs[1].text, '\u{FFFC}');
      expect(mentionOf(runs[1])?.label, '#REF-42');
      expect(mentionOf(runs[1])?.address, _address);
    });

    test('a link to anywhere else stays a link', () {
      final document = documentOf(
        Delta()..insert(
          'Example',
          attributes: {AppFlowyRichTextKeys.href: 'https://example.org'},
        ),
      );
      final runs = runsOf(codec.decode(codec.encode(document)));

      expect(mentionOf(runs.first), isNull);
      expect(
        runs.first.attributes?[AppFlowyRichTextKeys.href],
        'https://example.org',
      );
    });

    /// What a label comes home as, having been through markdown and back.
    String? homeLabel(String label) {
      final document = documentOf(
        mentionRun(Mention(address: _address, label: label)),
      );

      return mentionOf(
        runsOf(codec.decode(codec.encode(document))).first,
      )?.label;
    }

    test('a label carrying an unbalanced bracket keeps it, and the link', () {
      // The bracket closed the link early and took the address with it, and the
      // mention came home as plain text. Escaped rather than dropped, so the
      // name comes back the name it was.
      final document = documentOf(
        mentionRun(
          Mention(address: _address, label: '%Deuxième version] final'),
        ),
      );

      expect(
        codec.encode(document).trim(),
        r'[%Deuxième version\] final](/r/record/42)',
      );
      expect(homeLabel('%Deuxième version] final'), '%Deuxième version] final');
    });

    test(
      'a label that is an address stays one word, and stays the mention',
      () {
        // What a member with no name is called. The parser helped itself to the
        // email, pulling it out as a `mailto:` of its own — leaving a chip
        // holding nothing but '@' and the address linked beside it.
        expect(
          homeLabel('@francois.pluchino@fxp.io'),
          '@francois.pluchino@fxp.io',
        );
      },
    );

    test('a label wearing markup is read as the words it is', () {
      expect(homeLabel('@Ada *Lovelace*'), '@Ada *Lovelace*');
      expect(homeLabel('@a_b_c'), '@a_b_c');
      expect(homeLabel('@back`tick'), '@back`tick');
      expect(homeLabel(r'@back\slash'), r'@back\slash');
    });
  });

  testWidgets(
    'an editor with no mention source still draws the mentions already written',
    (tester) async {
      // A reply box or a read-only page offers no trigger and must still render
      // what somebody else wrote.
      final state = EditorState(document: sentence());
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              editorState: state,
              editable: false,
              features: const RichTextFeatures([
                LinkFeature(),
                MentionFeature(),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#REF-42'), findsOneWidget);
      expect(find.byType(MentionChip), findsOneWidget);
    },
  );

  testWidgets('a mention reads at the size of the text it stands in', (
    tester,
  ) async {
    // The chip is a widget, so it inherits nothing from the run it replaces:
    // fixed to a page's size, it came out bigger than the sentence around it
    // everywhere else — a message, a composer.
    final state = EditorState(document: sentence());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextViewer(
            editorState: state,
            textStyle: RichTextTheme.fallback.fieldText,
            features: const RichTextFeatures([LinkFeature(), MentionFeature()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('#REF-42')).style?.fontSize,
      RichTextTheme.fallback.fieldText.fontSize,
    );
  });

  testWidgets('a view draws the mentions it holds', (tester) async {
    // A mention is one placeholder character and a decorator: a view mounted
    // without the decorator renders it as nothing at all.
    final state = EditorState(document: sentence());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextViewer(
            editorState: state,
            features: const RichTextFeatures([LinkFeature(), MentionFeature()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MentionChip), findsOneWidget);
    expect(find.text('#REF-42'), findsOneWidget);
  });

  test(
    'typing right against a mention writes plain text, not more mention',
    () async {
      // The report that made this a test: the caret looked stuck to the right of
      // a tag and nothing appeared. The editor gives a typed character the
      // attributes of the one before it, so the letter was joining the mention's
      // run — and the run is drawn as one chip, so it vanished.
      MentionSources();

      final state = EditorState(document: sentence());
      addTearDown(state.dispose);
      final node = state.document.root.children.first;

      await state.apply(state.transaction..insertText(node, 6, 'a'));

      final runs = runsOf(state.document);

      expect(runs.map((run) => run.text).join(), 'Voir \u{FFFC}a demain');
      expect(runs.where((run) => mentionOf(run) != null), hasLength(1));
      expect(mentionOf(runs[1])?.label, '#REF-42');
    },
  );

  testWidgets('clicking a mention opens its card, and Escape closes it', (
    tester,
  ) async {
    // Its own card rather than the record's page: a mention is read in passing,
    // and leaving the document to find out who was named is what a card saves.
    container.registerSingleton<MentionSources>(MentionSources());

    final state = EditorState(document: sentence());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextEditor(
            editorState: state,
            editable: false,
            features: const RichTextFeatures([LinkFeature(), MentionFeature()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MentionChip));
    await tester.pumpAndSettle();

    // The label the document already holds, so the card never opens empty
    // while the record is read. Nothing registered knows a flow here, so
    // there is nothing to open either.
    expect(find.text('#REF-42'), findsNWidgets(2));
    expect(find.text('Open'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('#REF-42'), findsOneWidget);
  });
}
