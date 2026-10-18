/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_test/flutter_test.dart';

class _Holder implements ActiveHolder {
  @override
  bool active = true;
}

void main() {
  testWidgets('pauses a list while its tickers are off', (tester) async {
    final list = _Holder();

    await tester.pumpWidget(
      TickerMode(
        enabled: false,
        child: ListActivity(list: list, child: const SizedBox()),
      ),
    );

    expect(list.active, isFalse);

    await tester.pumpWidget(
      TickerMode(
        enabled: true,
        child: ListActivity(list: list, child: const SizedBox()),
      ),
    );

    expect(list.active, isTrue);
  });

  testWidgets('pauses every holder of a screen, and a list the page leaves out', (tester) async {
    final rows = _Holder();
    final counts = _Holder();

    Widget activity({required bool shown}) => TickerMode(
      enabled: true,
      child: ListActivity.all(
        lists: [rows, counts],
        shown: shown,
        child: const SizedBox(),
      ),
    );

    await tester.pumpWidget(activity(shown: false));

    expect((rows.active, counts.active), (false, false));

    await tester.pumpWidget(activity(shown: true));

    expect((rows.active, counts.active), (true, true));
  });
}
