/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Kept extends LogListener {
  _Kept({this.isEnabled = true});

  @override
  final bool isEnabled;

  final messages = <String>[];

  @override
  void onData(LogRecord record) => messages.add(record.message);
}

void main() {
  test('the records go to the enabled listeners of the container, those added later included', () async {
    await container.reset(dispose: false);

    final given = _Kept();
    final added = _Kept();
    final disabled = _Kept(isEnabled: false);

    initializeLogger(logLevel: Level.INFO, listeners: [given, disabled]);
    getService<LogListeners>().add(added);
    Logger('test').info('hello');
    await Future<void>.delayed(Duration.zero);

    expect(given.messages, ['hello']);
    expect(added.messages, ['hello']);
    expect(disabled.messages, isEmpty);
  });
}
