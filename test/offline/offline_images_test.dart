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

/// Marks `items` synchronizable so the `/items` API mirrors offline.
class _MockMetadataProvider implements MetadataProvider {
  const _MockMetadataProvider();

  static const _item = MetadataModel(
    name: 'item',
    apiName: 'items',
    label: 'Item',
    labelPlural: 'Items',
    searchable: false,
    sortable: false,
    synchronizable: true,
    fields: {},
  );

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => const {
    'item': _item,
  };

  @override
  Future<MetadataModel?> getMetadata(String name) async =>
      name == 'item' ? _item : null;

  @override
  Future<void> fetchMetadatas() async {}

  @override
  bool get loading => false;

  @override
  dynamic get error => null;

  @override
  String? get prefix => null;

  @override
  void setPrefix(String? newPrefix) {}
}

class _Item extends BaseModel<_Item> {
  _Item(super.data);
}

class _ItemApi extends ApiModel<_Item> {
  _ItemApi({
    required Fetcher fetcher,
    required LocalStore localStore,
    required ImageMirror imageMirror,
  }) : super(
         '/items',
         fetcher: fetcher,
         offlineBindings: OfflineStores(
           localStore: localStore,
           imageMirror: imageMirror,
         ),
       );

  @override
  List<String>? get syncFields => const ['id', 'name', 'avatar'];

  @override
  List<SyncImageField> get syncImageFields => const [
    SyncImageField('avatar', variants: [ImageVariant(width: 64, height: 64)]),
  ];

  @override
  _Item fromJson(Map<String, dynamic> json) => _Item(json);
}

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final Map<String, Map<String, dynamic> Function(RequestOptions options)>
  routes = {};
  final Map<String, Uint8List Function(RequestOptions options)> byteRoutes = {};
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    final byteHandler = byteRoutes['${options.method} ${options.path}'];

    if (byteHandler != null) {
      return ResponseBody.fromBytes(
        byteHandler(options),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      );
    }

    final handler = routes['${options.method} ${options.path}'];

    if (handler == null) {
      return ResponseBody.fromString(
        '{"detail": "Not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode(handler(options)),
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

  const variantKey = '64x64|cover|webp';

  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late DriftLocalImageStore imageStore;
  late _ItemApi api;

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
      container.registerSingleton<MetadataProvider>(
        const _MockMetadataProvider(),
      );
    }
  });

  setUp(() async {
    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.httpClientAdapter = adapter;
    final fetcher = Fetcher.create(
      dio: dio,
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
      enableErrorTransform: false,
    );
    store = DriftLocalStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    imageStore = DriftLocalImageStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    await imageStore.open();
    api = _ItemApi(
      fetcher: fetcher,
      localStore: store,
      imageMirror: ImageMirror(store, imageStore, StorageDownloader(fetcher)),
    );
  });

  tearDown(() async {
    await store.close();
    await imageStore.close();
  });

  group('DriftLocalImageStore', () {
    test('round-trips a variant', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await imageStore.putVariant(
        'a/b.png',
        variantKey,
        bytes,
        width: 64,
        height: 64,
      );

      expect(await imageStore.getVariant('a/b.png', variantKey), bytes);
      expect(await imageStore.hasVariant('a/b.png', variantKey), isTrue);
      expect(await imageStore.paths(), ['a/b.png']);
    });

    test('best variant prefers the original then the largest', () async {
      await imageStore.putVariant(
        'a.png',
        '64x64|cover|webp',
        Uint8List.fromList([1]),
        width: 64,
        height: 64,
      );
      await imageStore.putVariant(
        'a.png',
        '256x256|cover|webp',
        Uint8List.fromList([2]),
        width: 256,
        height: 256,
      );

      expect(await imageStore.getBestVariant('a.png'), [2]);

      await imageStore.putVariant(
        'a.png',
        'autoxauto|cover|original',
        Uint8List.fromList([3]),
      );

      expect(await imageStore.getBestVariant('a.png'), [3]);
    });

    test('removePath drops every variant of the path', () async {
      await imageStore.putVariant('a.png', variantKey, Uint8List.fromList([1]));
      await imageStore.putVariant('b.png', variantKey, Uint8List.fromList([2]));

      await imageStore.removePath('a.png');

      expect(await imageStore.getVariant('a.png', variantKey), isNull);
      expect(await imageStore.paths(), ['b.png']);
    });

    test('clear empties the store', () async {
      await imageStore.putVariant('a.png', variantKey, Uint8List.fromList([1]));

      await imageStore.clear();

      expect(await imageStore.paths(), isEmpty);
    });
  });

  group('ImageMirror through ApiModel', () {
    test('sync prefetches the declared variants', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'name': 'One', 'avatar': 'avatars/a.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/a.png'] = (options) =>
          Uint8List.fromList([9, 9]);

      await api.sync();

      expect(await imageStore.hasVariant('avatars/a.png', variantKey), isTrue);

      final request = adapter.requests.last;
      expect(request.queryParameters['w'], '64');
      expect(request.queryParameters['h'], '64');
      expect(request.queryParameters['m'], 'cover');
      expect(request.queryParameters['e'], 'webp');
    });

    test('does not re-download an already stored variant', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'avatar': 'avatars/a.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/a.png'] = (options) =>
          Uint8List.fromList([9]);

      await api.sync();
      final downloads = adapter.requests
          .where((r) => r.path.contains('/storage/'))
          .length;

      await api.sync();

      expect(
        adapter.requests.where((r) => r.path.contains('/storage/')).length,
        downloads,
      );
    });

    test('replaced path is purged and the new one downloaded', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'avatar': 'avatars/old.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/old.png'] = (options) =>
          Uint8List.fromList([1]);
      await api.sync();

      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'avatar': 'avatars/new.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/new.png'] = (options) =>
          Uint8List.fromList([2]);
      await api.sync();

      expect(
        await imageStore.getVariant('avatars/old.png', variantKey),
        isNull,
      );
      expect(
        await imageStore.hasVariant('avatars/new.png', variantKey),
        isTrue,
      );
    });

    test('update purges the old path and downloads the new one', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'avatar': 'avatars/old.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/old.png'] = (options) =>
          Uint8List.fromList([1]);
      await api.sync();

      adapter.routes['PATCH /items/1'] = (options) => {
        'id': 1,
        'avatar': 'avatars/new.png',
      };
      adapter.byteRoutes['GET /storage/download/avatars/new.png'] = (options) =>
          Uint8List.fromList([2]);
      await api.update(1, _Item({'avatar': 'avatars/new.png'}));

      expect(
        await imageStore.getVariant('avatars/old.png', variantKey),
        isNull,
      );
      expect(
        await imageStore.hasVariant('avatars/new.png', variantKey),
        isTrue,
      );
    });

    test('a path still referenced by another record is kept', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'avatar': 'avatars/shared.png'},
        {'id': 2, 'avatar': 'avatars/shared.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/shared.png'] =
          (options) => Uint8List.fromList([1]);
      await api.sync();

      adapter.routes['GET /items'] = (options) => _page([
        {'id': 2, 'avatar': 'avatars/shared.png'},
      ]);
      await api.sync();

      expect(
        await imageStore.hasVariant('avatars/shared.png', variantKey),
        isTrue,
      );
    });

    test('a failed image download does not fail the sync', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'avatar': 'avatars/missing.png'},
      ]);

      await api.sync();

      expect(await api.cachedList(), hasLength(1));
      expect(
        await imageStore.hasVariant('avatars/missing.png', variantKey),
        isFalse,
      );
    });
  });
}
