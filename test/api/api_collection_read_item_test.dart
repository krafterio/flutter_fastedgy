/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi({required Fetcher fetcher}) : super('/things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MockRequest> requests;
  late _ThingApi api;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    requests = [];
    final fetcher = createMockFetcher(
      (request) async {
        requests.add(request);

        return const MockResponse.json({'id': 5, 'name': 'Cinq'});
      },
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );

    api = _ThingApi(fetcher: fetcher);
  });

  test('a row read by its id asks for the fields of the collection and stays out of it', () async {
    final collection = ApiCollection<_Thing>(
      api,
      fields: const ['+', 'owner.name'],
      autoRefreshOnChange: false,
    );
    addTearDown(collection.dispose);

    final thing = await collection.readItem(5);

    expect(thing.getString('name'), 'Cinq');
    expect(requests.single.path, endsWith('/things/5'));
    expect(requests.single.headers['X-Fields'], '+,owner.name');
    expect(collection.items, isEmpty);
  });
}
