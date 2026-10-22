/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_test/flutter_test.dart';

import 'list_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingApi api;

  setUp(() async {
    await setUpList();
    api = ThingApi(ThingServer().fetcher);
  });

  test(
    'hands what is typed to the list, and shows a search cleared elsewhere',
    () async {
      final list = DataIterator<Thing>(api);
      final controller = DataSearchController(list);

      controller.text = 'lamp';

      expect(list.search, 'lamp');

      list.search = '';

      expect(controller.text, isEmpty);

      controller.dispose();
      list.dispose();
    },
  );

  test(
    'shows the search of the list it is given, and leaves the one it left',
    () async {
      final first = DataIterator<Thing>(api)..search = 'lamp';
      final second = DataIterator<Thing>(api)..search = 'desk';
      final controller = DataSearchController();

      controller.list = first;

      expect(controller.text, 'lamp');

      controller.list = second;
      first.search = 'chair';

      expect(controller.text, 'desk');

      controller.text = 'table';

      expect(second.search, 'table');
      expect(first.search, 'chair');

      controller.dispose();
      first.dispose();
      second.dispose();
    },
  );
}
