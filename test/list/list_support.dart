/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_metadata.dart';

class Thing extends BaseModel<Thing> {
  Thing(super.data);
}

class ThingApi extends ApiModel<Thing> {
  ThingApi(Fetcher fetcher, {String prefix = '/acme'})
    : super(prefix, modelName: 'thing', fetcher: fetcher);

  @override
  Thing fromJson(Map<String, dynamic> json) => Thing(json);
}

/// A server of [rows] things, answering a list by its window and keeping what
/// it is asked.
class ThingServer {
  ThingServer({this.rows = 120});

  int rows;

  final requests = <MockRequest>[];

  /// Held back in turn by the next lists, so a test decides which answers
  /// first.
  final gates = <Completer<void>>[];

  /// Answers a request before the list does, when it returns one.
  FutureOr<MockResponse?> Function(MockRequest request)? answer;

  late final Fetcher fetcher = createMockFetcher(
    _respond,
    enableAuth: false,
    enableTimezone: false,
    enableRefreshToken: false,
  );

  /// The reads of the list, in order.
  List<MockRequest> get lists => [
    for (final request in requests)
      if (request.method == 'GET' && request.path.endsWith('/things')) request,
  ];

  Future<MockResponse> _respond(MockRequest request) async {
    requests.add(request);

    final custom = await answer?.call(request);

    if (custom != null) {
      return custom;
    }

    if (request.method != 'GET' || !request.path.endsWith('/things')) {
      return const MockResponse.json({});
    }

    if (gates.isNotEmpty) {
      await gates.removeAt(0).future;
    }

    final limit = request.queryParameters['limit'] as int? ?? 50;
    final offset = request.queryParameters['offset'] as int? ?? 0;
    final last = (offset + limit).clamp(0, rows);

    return MockResponse.json({
      'items': [
        for (var id = offset + 1; id <= last; id++)
          {'id': id, 'name': 'Thing $id'},
      ],
      'total': rows,
      'limit': limit,
      'offset': offset,
      'total_pages': (rows / limit).ceil(),
    });
  }
}

/// What a read sent: its window, its filter, its fields, its order.
Map<String, Object?> sent(MockRequest request) {
  final filter = request.headers['X-Filter'] as String?;

  return {
    'offset': request.queryParameters['offset'],
    'limit': request.queryParameters['limit'],
    'filter': filter == null || filter.isEmpty ? null : jsonDecode(filter),
    'fields': request.headers['X-Fields'],
    'order': request.queryParameters['order_by'],
  };
}

/// The services a list reads through: the bus, the metadata of the things,
/// an empty device storage.
Future<FakeMetadataProvider> setUpList({
  bool sortable = false,
  String? sortableField,
  Map<String, MetadataField> fields = const {},
  Map<String, Object> stored = const {},
}) async {
  await container.reset(dispose: false);
  container.registerSingleton<Bus>(Bus());

  final metadata = FakeMetadataProvider({
    'thing': metaModel(
      'thing',
      apiName: 'things',
      sortable: sortable,
      sortableField: sortableField,
      fields: {
        'id': metaField('id', type: 'integer'),
        'name': metaField('name', type: 'char', searchable: true),
        ...fields,
      },
    ),
  });

  container.registerSingleton<MetadataProvider>(metadata);
  SharedPreferences.setMockInitialValues(stored);

  return metadata;
}

/// Lets the reads and the turns of the list settle.
Future<void> settle() async {
  for (var turn = 0; turn < 10; turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
