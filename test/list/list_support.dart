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
    'custom_view': metaModel(
      'custom_view',
      apiName: 'custom_views',
      fields: {'name': metaField('name', type: 'char')},
    ),
    'custom_view_favorite': metaModel(
      'custom_view_favorite',
      apiName: 'custom_view_favorites',
      fields: {'view': metaField('view', type: 'many2one')},
    ),
  });

  container.registerSingleton<MetadataProvider>(metadata);
  SharedPreferences.setMockInitialValues(stored);

  return metadata;
}

/// Waits until [done] holds, two seconds at most.
Future<void> until(bool Function() done) async {
  for (var turn = 0; turn < 400 && !done(); turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Lets the reads and the turns of the list settle.
Future<void> settle() async {
  for (var turn = 0; turn < 10; turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// The custom views and the favorites of a [ThingServer], held in memory.
class ViewServer {
  ViewServer(this.server) {
    server.answer = _answer;
  }

  final ThingServer server;

  final views = <Map<String, dynamic>>[];
  final favorites = <Map<String, dynamic>>[];
  var _next = 100;

  /// Answers the next write of a view with this, once.
  MockResponse? refuse;

  /// A view of the things, editable and of the default list unless said.
  Map<String, dynamic> add(Map<String, dynamic> view) {
    final row = {
      'id': ++_next,
      'model': 'thing',
      'scope': '',
      'user': null,
      'filters': null,
      'order_by': null,
      'group_by': null,
      'display_fields': null,
      'sequence': 0,
      'is_default': false,
      'editable': true,
      ...view,
    };

    views.add(row);

    return row;
  }

  Map<String, dynamic>? _view(Object? id) =>
      views.where((view) => view['id'] == id).firstOrNull;

  bool _holds(Map<String, dynamic> row, Object? filter) {
    final rules = filter is List ? filter : const [];

    return rules.every((rule) {
      if (rule is! List || rule.isEmpty) {
        return true;
      }

      final path = '${rule[0]}'.split('.');
      Object? value = row;

      for (final name in path) {
        value = value is Map ? value[name] : null;

        if (name == 'view' && value is! Map) {
          value = _view(value);
        }
      }

      return switch (rule[1]) {
        '=' => value == rule[2],
        'is true' => value == true,
        _ => true,
      };
    });
  }

  Object? _filterOf(MockRequest request) {
    final raw = request.headers['X-Filter'] as String?;

    return raw == null || raw.isEmpty ? null : jsonDecode(raw);
  }

  Object? _idIn(String path) => int.tryParse(path.split('/').last);

  FutureOr<MockResponse?> _answer(MockRequest request) {
    final path = request.path;
    final body = request.body is Map ? {...request.body as Map} : const {};

    if (path.contains('/custom_view') && request.method != 'GET') {
      final refused = refuse;

      if (refused != null) {
        refuse = null;

        return refused;
      }
    }

    if (path.contains('/custom_view_favorites')) {
      switch (request.method) {
        case 'GET':
          final nested = '${request.headers['X-Fields']}'.contains('view.');
          final rows = [
            for (final favorite in favorites)
              if (_holds({
                ...favorite,
                'view': _view(favorite['view']),
              }, _filterOf(request)))
                {
                  'id': favorite['id'],
                  'view': nested ? _view(favorite['view']) : favorite['view'],
                },
          ];

          return MockResponse.json({'items': rows, 'total': rows.length});
        case 'POST':
          final row = {'id': ++_next, 'view': body['view']};

          favorites.add(row);

          return MockResponse.json(row);
        case 'DELETE':
          favorites.removeWhere((favorite) => favorite['id'] == _idIn(path));

          return const MockResponse.empty();
      }
    }

    if (path.contains('/custom_views')) {
      final id = _idIn(path);

      switch (request.method) {
        case 'GET' when id != null:
          final view = _view(id);

          return view == null
              ? const MockResponse.error(404)
              : MockResponse.json(view);
        case 'GET':
          final rows = [
            for (final view in views)
              if (_holds(view, _filterOf(request))) view,
          ];

          return MockResponse.json({'items': rows, 'total': rows.length});
        case 'POST':
          return MockResponse.json(add({...body.cast<String, dynamic>()}));
        case 'PATCH':
          final view = _view(id)!..addAll(body.cast<String, dynamic>());

          return MockResponse.json(view);
        case 'DELETE':
          views.removeWhere((view) => view['id'] == id);

          return const MockResponse.empty();
      }
    }

    return null;
  }
}
