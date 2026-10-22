/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  EditorState longDocument(WidgetTester tester) {
    final state = EditorState(
      document: Document.blank()
        ..insert(
          [0],
          [
            for (var line = 0; line < 40; line += 1)
              paragraphNode(delta: Delta()..insert('Line $line')),
          ],
        ),
    );
    addTearDown(state.dispose);

    return state;
  }

  Widget host(EditorState state, {required double height, double? maxHeight}) =>
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: height,
              child: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
                scrollable: maxHeight == null,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ),
      );

  testWidgets('the auto scroll margin fits in a short editor', (tester) async {
    final state = longDocument(tester);

    await tester.pumpWidget(host(state, height: 150));
    await tester.pumpAndSettle();

    expect(state.autoScrollEdgeOffset, lessThanOrEqualTo(75));

    await tester.pumpWidget(host(state, height: 600));
    await tester.pumpAndSettle();

    expect(state.autoScrollEdgeOffset, 220);
  });

  testWidgets('the auto scroll margin fits in a capped field', (tester) async {
    final state = longDocument(tester);

    await tester.pumpWidget(host(state, height: 400, maxHeight: 80));
    await tester.pumpAndSettle();

    expect(state.autoScrollEdgeOffset, lessThanOrEqualTo(40));
  });

  testWidgets('a tap in the text of a short editor does not freeze the app', (
    tester,
  ) async {
    final state = longDocument(tester);

    await tester.pumpWidget(host(state, height: 150));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Line 3', findRichText: true).first);
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(state.selection, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'a tap in the text does not freeze the app when the editor shrinks in the same frame',
    (tester) async {
      final state = longDocument(tester);

      await tester.pumpWidget(host(state, height: 600));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Line 3', findRichText: true).first);
      await tester.pumpWidget(host(state, height: 150));
      for (var frame = 0; frame < 20; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(state.selection, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
