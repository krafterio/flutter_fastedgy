/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Syncing a full model used to walk its whole manifest on every call, a
/// request per page even when nothing had moved. The sync state route answers
/// that question in one request, and the cursor left by the last completed
/// sync turns the walk into a delta.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// The mirror partitions on a scope; with no param in the path it comes from
/// the resolver the app registers globally.
class _Scope implements OfflineContextParamsResolver {
  @override
  Map<String, Object?> resolve() => {'workspace': 'acme'};
}

class _Metadatas implements MetadataProvider {
  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => {'item': _model};

  @override
  Future<MetadataModel?> getMetadata(String name) async =>
      name == 'item' ? _model : null;

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

const _model = MetadataModel(
  name: 'item',
  apiName: 'items',
  label: 'Item',
  labelPlural: 'Items',
  searchable: false,
  sortable: false,
  synchronizable: true,
  synchronizableMode: 'full',
  fields: {},
);

class _Item extends BaseModel<_Item> {
  _Item(super.data);

  String get name => getString('name') ?? '';
}

class _ItemApi extends ApiModel<_Item> {
  _ItemApi({
    required super.fetcher,
    required Replica replica,
    required LocalStore localStore,
  }) : super(
         '',
         modelName: 'item',
         offlineBindings: OfflineStores(
           localStore: localStore,
           replica: replica,
         ),
       );

  @override
  List<String>? get syncFields => const ['id', 'name', 'updated_at'];

  @override
  int get syncPageSize => 50;

  @override
  _Item fromJson(Map<String, dynamic> json) => _Item(json);
}

const _schema = LocalSchema({
  'item': LocalModelSchema(
    name: 'item',
    apiName: 'items',
    fields: {
      'id': LocalFieldSchema(name: 'id', type: 'integer'),
      'name': LocalFieldSchema(name: 'name', type: 'char'),
      'updated_at': LocalFieldSchema(name: 'updated_at', type: 'datetime'),
    },
  ),
});

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> calls = [];
  final Map<String, Map<String, dynamic> Function(RequestOptions options)>
  routes = {};

  List<String> get paths => calls.map((options) => options.path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);

    return ResponseBody.fromString(
      jsonEncode(
        routes['${options.method} ${options.path}']?.call(options) ??
            const <String, dynamic>{},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'limit': items.length,
  'offset': 0,
  'total_pages': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Adapter adapter;
  late DriftLocalStore store;
  late ReplicaStore replicaStore;
  late Replica replica;
  late _ItemApi api;

  const one = {'id': 1, 'name': 'One', 'updated_at': '2026-09-01T10:00:00Z'};
  const two = {'id': 2, 'name': 'Two', 'updated_at': '2026-09-02T10:00:00Z'};

  void serves(
    List<Map<String, dynamic>> items, {
    String? freshest,
    int? count,
  }) {
    adapter.routes['GET /dataset/sync-state'] = (_) => {
      'items': [
        {
          'model': 'item',
          'mode': 'full',
          'count': count ?? items.length,
          'updated_at':
              freshest ?? (items.isEmpty ? null : items.last['updated_at']),
        },
      ],
    };
    adapter.routes['GET /items'] = (options) {
      final fields = '${options.headers['X-Fields'] ?? ''}';
      final filter = '${options.headers['X-Filter'] ?? ''}';
      final selected = filter.contains('updated_at')
          ? items
                .where(
                  (item) =>
                      '${item['updated_at']}'.compareTo(_since(filter)) >= 0,
                )
                .toList()
          : items;

      return _page([
        for (final item in selected)
          if (fields == 'id') {'id': item['id']} else item,
      ]);
    };
  }

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    if (!hasService<ApiModelEngineProvider>()) {
      container.registerSingleton<ApiModelEngineProvider>(
        const OfflineApiModelEngineProvider(),
      );
    }

    if (!hasService<MetadataProvider>()) {
      container.registerSingleton<MetadataProvider>(_Metadatas());
    }

    if (!hasService<OfflineContextParams>()) {
      container.registerSingleton<OfflineContextParams>(OfflineContextParams());
    }

    getService<OfflineContextParams>().register(_Scope(), global: true);
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    adapter = _Adapter();
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    replicaStore = ReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    await replicaStore.open();
    replica = Replica.withSchema(replicaStore, _schema);
    api = _ItemApi(
      fetcher: Fetcher.create(
        dio: Dio(BaseOptions(baseUrl: 'http://localhost'))
          ..httpClientAdapter = adapter,
        bus: getService<Bus>(),
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
        enableConnectionRetry: false,
        enableLogging: false,
        enableErrorTransform: false,
      ),
      replica: replica,
      localStore: store,
    );
  });

  tearDown(() async {
    await store.close();
    await replicaStore.close();
  });

  test(
    'the first sync walks the manifest and remembers where it left off',
    () async {
      serves([one, two]);

      await api.sync();

      expect(await replicaStore.getAll('item', 'acme'), hasLength(2));
      final cursor = await replicaStore.cursor('item', 'acme');
      expect(cursor?.updatedAt, two['updated_at']);
      expect(cursor?.count, 2);
    },
  );

  test('a second sync with nothing moved costs one request', () async {
    serves([one, two]);
    await api.sync();

    adapter.calls.clear();
    await api.sync();

    expect(adapter.paths, ['/dataset/sync-state']);
  });

  test(
    'a fresher record is pulled by its date, without listing the ids',
    () async {
      serves([one, two]);
      await api.sync();

      const edited = {
        'id': 1,
        'name': 'Renamed',
        'updated_at': '2026-09-03T10:00:00Z',
      };
      serves([edited, two], freshest: '2026-09-03T10:00:00Z', count: 2);
      adapter.calls.clear();
      await api.sync();

      expect((await api.cachedGet(1))?.name, 'Renamed');
      expect(
        adapter.calls.where((call) => call.headers['X-Fields'] == 'id'),
        isEmpty,
        reason: 'nothing was deleted',
      );
    },
  );

  test(
    'a record gone from the server is pruned once the counts disagree',
    () async {
      serves([one, two]);
      await api.sync();

      serves([two], freshest: two['updated_at'] as String, count: 1);
      adapter.calls.clear();
      await api.sync();

      expect(await api.cachedGet(1), isNull);
      expect(await api.cachedList(), hasLength(1));
      expect(
        adapter.calls.where((call) => call.headers['X-Fields'] == 'id'),
        hasLength(1),
      );
    },
  );

  test(
    'a server that cannot answer the state keeps the manifest walk',
    () async {
      adapter.routes['GET /items'] = (_) => _page([one, two]);

      await api.sync();

      expect(await api.cachedList(), hasLength(2));
      expect(await replicaStore.cursor('item', 'acme'), isNull);
    },
  );
}

String _since(String filter) {
  final match = RegExp(r'"([0-9T:\-\.Z+]{8,})"').allMatches(filter).lastOrNull;

  return match?.group(1) ?? '';
}
