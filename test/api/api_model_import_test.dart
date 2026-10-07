/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi({required Fetcher fetcher}) : super('/things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

void main() {
  late List<MockRequest> sent;
  late _ThingApi api;

  final file = utf8.encode('name;kcal\npomme;52\n');

  setUp(() {
    initializeContainer();
    container.registerSingleton<Bus>(Bus());
    sent = [];
    api = _ThingApi(
      fetcher: createMockFetcher(
        (request) {
          sent.add(request);

          return const MockResponse.json({
            'success': 1,
            'errors': 0,
            'created': 1,
            'updated': 0,
          });
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  tearDown(() => container.reset());

  FormData form() => sent.single.body! as FormData;

  test('an import sends the file alone when no delimiter is given', () async {
    await api.import(file, 'things.csv');

    expect(sent.single.path, '/things/import');
    expect(form().files.single.value.filename, 'things.csv');
    expect(form().fields, isEmpty);
  });

  test('an import sends the delimiter of a csv along with the file', () async {
    await api.import(file, 'things.csv', delimiter: ';');

    expect(
      {for (final field in form().fields) field.key: field.value},
      {'delimiter': ';'},
    );
  });
}
