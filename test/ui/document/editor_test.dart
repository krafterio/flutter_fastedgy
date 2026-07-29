/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  Future<EditorState> pumpEditor(
    WidgetTester tester, {
    required Document document,
    String? emptyPlaceholder,
    Widget? header,
    Widget? cover,
  }) async {
    final state = EditorState(document: document);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentEditor(
            editorState: state,
            emptyPlaceholder: emptyPlaceholder,
            header: header,
            cover: cover,
          ),
        ),
      ),
    );
    // The editor registers its gesture interceptor after the first frame, and
    // Skeleton-free as it is, one more frame settles the placeholder.
    await tester.pump();

    return state;
  }

  testWidgets(
    'an empty document says what it holds none of while nothing is focused',
    (tester) async {
      await pumpEditor(
        tester,
        document: Document.blank(withInitialText: true),
        emptyPlaceholder: t('No description'),
      );

      expect(
        find.text(t('No description'), findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('a written document shows no placeholder', (tester) async {
    await pumpEditor(
      tester,
      document: markdownToDocument('Quatre emails sur 14 jours.'),
      emptyPlaceholder: t('No description'),
    );

    expect(find.text(t('No description'), findRichText: true), findsNothing);
  });

  testWidgets(
    'a cover spans the page while the header stays on the text column',
    (tester) async {
      await pumpEditor(
        tester,
        document: markdownToDocument('Quatre emails sur 14 jours.'),
        cover: const SizedBox(height: 200, key: ValueKey('cover')),
        header: const Text('Sujet'),
      );

      final cover = tester.getSize(find.byKey(const ValueKey('cover')));
      final header = tester.getSize(find.text('Sujet'));

      // What a cover is: edge to edge, where the header is bound to the column
      // the blocks are centred on.
      expect(cover.width, greaterThan(header.width));
      expect(cover.width, tester.getSize(find.byType(DocumentEditor)).width);
    },
  );

  testWidgets(
    'an empty document stays blank when no empty placeholder is given',
    (tester) async {
      await pumpEditor(tester, document: Document.blank(withInitialText: true));

      expect(find.text(t('No description'), findRichText: true), findsNothing);
      expect(
        find.text(
          t('Write, or type “/” to insert a block…'),
          findRichText: true,
        ),
        findsNothing,
      );
    },
  );
}
