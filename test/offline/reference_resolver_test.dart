/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _MockMetadataProvider implements MetadataProvider {
  final Map<String, MetadataModel> _map;

  _MockMetadataProvider(this._map);

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => _map;

  @override
  Future<MetadataModel?> getMetadata(String name) async => _map[name];

  @override
  Future<void> fetchMetadatas() async {}

  @override
  bool get loading => false;

  @override
  dynamic get error => null;

  @override
  String? get prefix => null;

  @override
  String get scope => '';

  @override
  void setPrefix(String? newPrefix) {}
}

MetadataModel _meta(
  String name,
  String apiName, {
  required bool synchronizable,
}) => MetadataModel(
  name: name,
  apiName: apiName,
  label: name,
  labelPlural: name,
  searchable: false,
  sortable: false,
  synchronizable: synchronizable,
  fields: const {},
);

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function(RequestOptions)> routes = {};
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    calls.add('${options.method} ${options.path}');
    final handler = routes['${options.method} ${options.path}'];

    return ResponseBody.fromString(
      handler == null
          ? '{"detail": "Not found"}'
          : jsonEncode(handler(options)),
      handler == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _schema = LocalSchema({
  'thing': LocalModelSchema(
    name: 'thing',
    apiName: 'things',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
    },
  ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late ReplicaStore replicaStore;
  late Replica replica;
  late ReferenceResolver resolver;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    adapter = _ScriptedAdapter();
    final fetcher = Fetcher.create(
      dio: Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = adapter,
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
      enableErrorTransform: false,
    );
    replicaStore = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await replicaStore.open();
    replica = Replica.withSchema(replicaStore, _schema);
    resolver = ReferenceResolver(
      metadata: _MockMetadataProvider({
        'thing': _meta('thing', 'things', synchronizable: true),
        'live': _meta('live', 'lives', synchronizable: false),
        'parent': const MetadataModel(
          name: 'parent',
          apiName: 'parents',
          label: 'parent',
          labelPlural: 'parent',
          searchable: false,
          sortable: false,
          fields: {
            'thing_ref': MetadataField(
              name: 'thing_ref',
              label: 'Thing',
              type: 'many2one',
              readonly: false,
              required: false,
              searchable: false,
              extra: false,
              filterOperators: [],
              target: 'thing',
            ),
          },
        ),
      }),
      replica: replica,
      fetcher: fetcher,
    );
  });

  tearDown(() => replicaStore.close());

  test(
    'a synchronizable target already replicated is served from the replica',
    () async {
      await replica.ensure('thing');
      await replicaStore.upsertAll(_schema.models['thing']!, '', [
        {'id': 1, 'name': 'Local'},
      ]);

      final record = await resolver.resolve('thing', 1);

      expect(record?['name'], 'Local');
      expect(adapter.calls, isEmpty);
    },
  );

  test('a synchronizable gap is filled from the server and stored', () async {
    adapter.routes['GET /things/1'] = (options) => {'id': 1, 'name': 'Server'};

    final first = await resolver.resolve('thing', 1);
    final second = await resolver.resolve('thing', 1);

    expect(first?['name'], 'Server');
    expect(second?['name'], 'Server');
    // Stored on the first resolve: the second reads the replica, not the network.
    expect(adapter.calls, ['GET /things/1']);
    expect((await replicaStore.getById('thing', '', 1))?['name'], 'Server');
  });

  test('a synchronizable gap offline resolves to null', () async {
    adapter.offline = true;

    expect(await resolver.resolve('thing', 1), isNull);
  });

  test(
    'a non-synchronizable target is fetched live and never stored',
    () async {
      adapter.routes['GET /lives/5'] = (options) => {'id': 5, 'name': 'Live'};

      final first = await resolver.resolve('live', 5);
      final second = await resolver.resolve('live', 5);

      expect(first?['name'], 'Live');
      expect(second?['name'], 'Live');
      // Not stored: every resolve hits the network.
      expect(adapter.calls, ['GET /lives/5', 'GET /lives/5']);
    },
  );

  test('a non-synchronizable target offline resolves to null', () async {
    adapter.offline = true;

    expect(await resolver.resolve('live', 5), isNull);
  });

  test('a scope prefixes the fetch path', () async {
    adapter.routes['GET /acme/things/7'] = (options) => {
      'id': 7,
      'name': 'Scoped',
    };

    final record = await resolver.resolve('thing', 7, scope: 'acme');

    expect(record?['name'], 'Scoped');
    expect(adapter.calls, ['GET /acme/things/7']);
  });

  test('resolveField follows a foreign key via its metadata target', () async {
    await replica.ensure('thing');
    await replicaStore.upsertAll(_schema.models['thing']!, '', [
      {'id': 1, 'name': 'Local'},
    ]);

    final target = await resolver.resolveField('parent', {
      'thing_ref': {'id': 1},
    }, 'thing_ref');

    expect(target?['name'], 'Local');
    expect(adapter.calls, isEmpty);
  });

  test('resolveField follows a generic reference via its \$model', () async {
    adapter.routes['GET /things/2'] = (options) => {'id': 2, 'name': 'Generic'};

    final target = await resolver.resolveField('parent', {
      'ref': {'\$model': 'thing', 'id': 2},
    }, 'ref');

    expect(target?['name'], 'Generic');
  });

  test('resolveField returns null for an empty reference', () async {
    expect(
      await resolver.resolveField('parent', {'thing_ref': null}, 'thing_ref'),
      isNull,
    );
    expect(adapter.calls, isEmpty);
  });
}
