/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

  /// Drags a selection with the mouse from the top of a scrollable editor 80
  /// high down to [to], holds it there, and gives the scroll offsets meanwhile
  /// with the selection the drag ends on.
  Future<(List<double>, Selection?)> holdDrag(
    WidgetTester tester, {
    required double to,
  }) async {
    final state = longDocument(tester);

    await tester.pumpWidget(host(state, height: 80));
    await tester.pumpAndSettle();

    final window = tester.getRect(find.byType(RichTextEditor));
    final drag = await tester.startGesture(
      window.topLeft + const Offset(20, 10),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= 10; step += 1) {
      await drag.moveTo(
        window.topLeft + Offset(20 + step * 5.0, 10 + step * (to - 10) / 10),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    final offsets = <double>[];
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      offsets.add(state.scrollableState!.position.pixels);
    }
    final selection = state.selection;
    await drag.up();
    await tester.pumpAndSettle();

    return (offsets, selection);
  }

  /// Where the scrolling went back the other way.
  List<int> turnsOf(List<double> offsets) {
    final steps = [
      for (var i = 1; i < offsets.length; i += 1)
        (offsets[i] - offsets[i - 1]).sign,
    ].where((sign) => sign != 0).toList();

    return [
      for (var i = 1; i < steps.length; i += 1)
        if (steps[i] != steps[i - 1]) i,
    ];
  }

  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets(
    'a mouse holding a selection in the middle of a short editor leaves the text still',
    (tester) async {
      final (offsets, _) = await holdDrag(tester, to: 40);

      expect(turnsOf(offsets), isEmpty);
      expect(offsets.last, offsets.first);
    },
    variant: desktop,
  );

  testWidgets(
    'a mouse holding a selection at the foot of a short editor keeps scrolling down',
    (tester) async {
      final (offsets, selection) = await holdDrag(tester, to: 76);

      expect(turnsOf(offsets), isEmpty);
      expect(offsets.last, greaterThan(offsets.first));
      expect(selection!.end.path.first, greaterThan(3));
    },
    variant: desktop,
  );
}
