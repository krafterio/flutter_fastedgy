/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _named(String label) => find.byWidgetPredicate(
  (widget) => widget is RawTooltip && widget.semanticsTooltip == label,
);

void main() {
  testWidgets(
    'opens in an application without Material, its buttons named for assistive technologies',
    (tester) async {
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, _) => builder(context),
          ),
          home: FullScreenImageViewer(images: const [], onSave: (_) async {}),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(_named('Close'), findsOneWidget);
      expect(_named('Reset zoom'), findsOneWidget);
      expect(_named('Download'), findsOneWidget);
    },
  );
}
