/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HoverPointerScope', () {
    late bool canHover;

    Widget probe() => Builder(
      builder: (context) {
        canHover = context.canHover;

        return const SizedBox.expand();
      },
    );

    testWidgets('starts from a desktop platform', (tester) async {
      await tester.pumpWidget(HoverPointerScope(child: probe()));
      expect(canHover, isTrue);

      await tester.pumpWidget(probe());
      expect(canHover, isTrue);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('starts from a mobile platform', (tester) async {
      await tester.pumpWidget(HoverPointerScope(child: probe()));
      expect(canHover, isFalse);

      await tester.pumpWidget(probe());
      expect(canHover, isFalse);
    }, variant: TargetPlatformVariant.mobile());

    testWidgets('follows the kind of the last pointer', (tester) async {
      await tester.pumpWidget(HoverPointerScope(child: probe()));
      expect(canHover, isFalse);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(10, 10));
      await tester.pump();
      expect(canHover, isTrue);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(canHover, isFalse);

      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(const Offset(30, 30));
      await trackpad.panZoomEnd();
      await tester.pump();
      expect(canHover, isTrue);
    });
  });
}
