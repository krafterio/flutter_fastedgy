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
import 'package:flutter_fastedgy/ui.dart'
    show documentImagePaths, richTextImages;

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
  String get scope => '';

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
  List<String>? get syncFields => const ['id', 'name', 'avatar', 'body'];

  @override
  List<SyncImageField> get syncImageFields => [
    const SyncImageField(
      'avatar',
      variants: [ImageVariant(width: 64, height: 64)],
    ),
    richTextImages('body'),
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

  _documentPaths();

  group('ImageMirror through ApiModel', () {
    test('sync prefetches the declared variants', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'name': 'One', 'avatar': 'avatars/a.png'},
      ]);
      adapter.byteRoutes['GET /storage/download/avatars/a.png'] = (options) =>
          Uint8List.fromList([9, 9]);

      await api.sync();

      expect(await imageStore.hasVariant('avatars/a.png', variantKey), isTrue);

      final request = adapter.requests.firstWhere(
        (options) => options.path.endsWith('avatars/a.png'),
      );
      expect(request.queryParameters['w'], '64');
      expect(request.queryParameters['h'], '64');
      expect(request.queryParameters['m'], 'cover');
      expect(request.queryParameters['e'], 'webp');
    });

    test('mirrors the images a payload nests', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {
          'id': 1,
          'name': 'One',
          'household': {'avatar': 'avatars/home.png'},
          'members': [
            {'avatar': 'avatars/ada.png'},
            {'avatar': 'avatars/linus.png'},
          ],
        },
      ]);

      for (final path in [
        'avatars/home.png',
        'avatars/ada.png',
        'avatars/linus.png',
      ]) {
        adapter.byteRoutes['GET /storage/download/$path'] = (options) =>
            Uint8List.fromList([7]);
      }

      await api.sync();

      for (final path in [
        'avatars/home.png',
        'avatars/ada.png',
        'avatars/linus.png',
      ]) {
        expect(await imageStore.hasVariant(path, variantKey), isTrue);
      }
    });

    test('mirrors the pictures a document holds in its text', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {
          'id': 1,
          'name': 'One',
          'body': 'Avant\n\n![](attachment:15?w=420&h=280)\n\nAprès ![](attachment:16)',
        },
      ]);

      for (final id in [15, 16]) {
        adapter.byteRoutes['GET /storage/download/attachments/$id'] = (
          options,
        ) => Uint8List.fromList([4]);
      }

      await api.sync();

      // The width the document reads them at, whatever size they are drawn.
      for (final id in [15, 16]) {
        expect(
          await imageStore.hasVariant('attachments/$id', '720xauto|cover|webp'),
          isTrue,
        );
      }
    });

    test('a later sync catches up a picture the mirror never got', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'name': 'One', 'body': '![](attachment:21)'},
      ]);
      // The server has nothing to serve for it yet: the download fails and the
      // variant stays missing.
      await api.sync();
      expect(
        await imageStore.hasVariant('attachments/21', '720xauto|cover|webp'),
        isFalse,
      );

      adapter.byteRoutes['GET /storage/download/attachments/21'] = (options) =>
          Uint8List.fromList([2]);

      // The record has not changed: only a pass that looks at every mirrored
      // path can still fetch it.
      await api.sync();

      expect(
        await imageStore.hasVariant('attachments/21', '720xauto|cover|webp'),
        isTrue,
      );
    });

    test('stops asking for a picture three passes did not find', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'name': 'One', 'avatar': 'avatars/gone.png'},
      ]);

      // No byte route for it: the download answers 404, pass after pass.
      for (var pass = 0; pass < 5; pass++) {
        await api.sync();
      }

      expect(
        adapter.requests.where(
          (options) => options.path.endsWith('avatars/gone.png'),
        ),
        hasLength(3),
      );
    });

    test('reading a record again re-indexes nothing else', () async {
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'name': 'One', 'avatar': 'avatars/a.png'},
        {'id': 2, 'name': 'Two', 'avatar': 'avatars/b.png'},
      ]);

      for (final name in ['a', 'b']) {
        adapter.byteRoutes['GET /storage/download/avatars/$name.png'] = (
          options,
        ) => Uint8List.fromList([1]);
      }

      await api.sync();
      final downloads = adapter.requests
          .where((options) => options.path.contains('/storage/'))
          .length;

      adapter.routes['GET /items/1'] = (options) => {
        'id': 1,
        'name': 'One',
        'avatar': 'avatars/a.png',
      };
      await api.get(1);

      // Nothing new in that record: no download, and no walk over the other
      // mirrored records to find that out.
      expect(
        adapter.requests.where((options) => options.path.contains('/storage/')),
        hasLength(downloads),
      );
    });

    test('never tries to download a file awaiting its upload', () async {
      // A record can reference a file that only exists locally, until its
      // buffered upload is replayed. The server knows no such path, so asking
      // it would fail — and warn — on every single pass.
      adapter.routes['GET /items'] = (options) => _page([
        {'id': 1, 'name': 'One', 'avatar': 'local://0001-0000'},
      ]);

      await api.sync();

      expect(
        adapter.requests.where((r) => r.path.contains('/storage/')),
        isEmpty,
      );
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
      adapter.byteRoutes['GET /storage/download/avatars/shared.png'] = (
        options,
      ) => Uint8List.fromList([1]);
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

void _documentPaths() {
  group('documentImagePaths', () {
    test('reads the attachments a text points at, and nothing else', () {
      expect(
        documentImagePaths(
          '![](attachment:15?w=420) puis ![](attachment:16) et ![](https://ailleurs/x.png)',
        ),
        {'attachments/15', 'attachments/16'},
      );
    });

    test('a text without a picture names none', () {
      expect(documentImagePaths('Rien du tout'), isEmpty);
    });
  });
}
