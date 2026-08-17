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

  Future<void> pump(WidgetTester tester, String? markdown) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RichTextMarkdown(
              features: defaultRichTextFeatures,
              markdown: markdown,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The blocks the view is drawing, straight from the state it holds.
  List<Node> blocks(WidgetTester tester) => tester
      .widget<RichTextViewer>(find.byType(RichTextViewer))
      .editorState
      .document
      .root
      .children;

  testWidgets('reads the markdown as the blocks it describes', (tester) async {
    await pump(tester, '# Le point\n\n- un flow en retard\n- deux relances');

    expect(blocks(tester).first.type, HeadingBlockKeys.type);
    expect(find.text('Le point', findRichText: true), findsOneWidget);
    expect(find.text('un flow en retard', findRichText: true), findsOneWidget);
  });

  testWidgets('says nothing where there is nothing to say, and still renders', (
    tester,
  ) async {
    await pump(tester, null);

    // Never a blockless document: it would render as a dead zone.
    expect(blocks(tester), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text arriving in pieces grows in place', (tester) async {
    // What an answer streaming in does. Decoding it into a document of its own
    // on every token would rebuild every block that did not change — the text
    // flashing, and each picture in it fetched again.
    await pump(tester, 'Trois flows sont en retard.\n\nLe premier');
    final untouched = blocks(tester).first;

    await pump(tester, 'Trois flows sont en retard.\n\nLe premier est le J7.');
    await tester.pump();

    expect(identical(blocks(tester).first, untouched), isTrue);
    expect(
      find.text('Le premier est le J7.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a whole rewrite still lands', (tester) async {
    await pump(tester, 'Trois flows sont en retard.');

    await pump(tester, 'Aucun flow en retard.');
    await tester.pump();

    expect(
      find.text('Aucun flow en retard.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Trois flows sont en retard.', findRichText: true),
      findsNothing,
    );
  });
}
