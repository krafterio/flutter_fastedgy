/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  testWidgets('a page left mid-fling writes nothing on the list it disposed', (
    tester,
  ) async {
    final state = EditorState(
      document: Document.blank()
        ..insert(
          [0],
          [
            for (var i = 0; i < 60; i++)
              paragraphNode(delta: Delta()..insert('Bloc $i')),
          ],
        ),
    );
    addTearDown(state.dispose);

    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: state,
            scrollable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(RichTextEditor),
      const Offset(0, -600),
      2000,
    );
    await tester.pump();

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
