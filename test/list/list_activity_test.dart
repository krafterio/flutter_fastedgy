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
}
