/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the card the way the "/" entry does, and hands back the context it was
/// opened from so a test can assert on what it drew.
Future<void> _open(WidgetTester tester, {ImageFilePicker? pickFile}) async {
  final state = EditorState(
    document: Document.blank()..insert([0], [paragraphNode(text: 'Une ligne')]),
  );
  addTearDown(state.dispose);

  late BuildContext anchor;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            anchor = context;

            return RichTextEditor(
              editorState: state,
              features: const RichTextFeatures([]),
            );
          },
        ),
      ),
    ),
  );

  state.selection = Selection.collapsed(Position(path: const [0], offset: 0));
  await tester.pumpAndSettle();

  showImageEditor(anchor, state, state.selection!, pickFile: pickFile);
  await tester.pumpAndSettle();
}

void main() {
  group('showImageEditor', () {
    testWidgets('offers this device when the application supplies a picker', (
      tester,
    ) async {
      await _open(tester, pickFile: () async => File('nowhere.png'));

      expect(find.text('Choose an image'), findsOneWidget);
    });

    testWidgets('offers an address alone when it does not', (tester) async {
      await _open(tester);

      // Never a button that opens nothing: an application with no file plugin
      // gets the half of the card that works, not a dead half beside it.
      expect(find.text('Choose an image'), findsNothing);
      expect(find.text('Paste an image address'), findsOneWidget);
    });
  });
}
