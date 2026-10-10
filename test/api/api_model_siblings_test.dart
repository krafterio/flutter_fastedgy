/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi(Fetcher fetcher) : super('/acme/things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  test(
    'asks the neighbours of a record in the list its filter and its order read',
    () async {
      final requests = <MockRequest>[];
      final api = _ThingApi(
        createMockFetcher(
          (request) {
            requests.add(request);

            return MockResponse.json(
              request.path.endsWith('/7/siblings')
                  ? {'previous': 6, 'next': null}
                  : null,
            );
          },
          enableAuth: false,
          enableTimezone: false,
          enableRefreshToken: false,
        ),
      );

      expect(
        await api.siblings(
          7,
          filter: ['name', 'icontains', 'lamp'],
          orderBy: ['name:asc'],
        ),
        (previous: 6, next: null),
      );
      expect(requests.single.path, '/acme/things/7/siblings');
      expect(requests.single.queryParameters['order_by'], 'name:asc');
      expect(jsonDecode(requests.single.headers['X-Filter'] as String), [
        'name',
        'icontains',
        'lamp',
      ]);

      expect(await api.siblings(8), (previous: null, next: null));
      expect(requests.last.headers.containsKey('X-Filter'), isFalse);
    },
  );
}
