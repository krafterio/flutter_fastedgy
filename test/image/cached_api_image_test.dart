/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart' hide ImageCache;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final List<String> calls = [];
  final List<String> renditions = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    renditions.add(
      '${options.queryParameters['w']}x${options.queryParameters['h']}',
    );

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    return ResponseBody.fromBytes(
      _png,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late DriftLocalImageStore imageStore;

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

    imageStore = DriftLocalImageStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await imageStore.open();

    container.registerSingleton<ImageCache>(ImageCache(getService<Bus>()));
    container.registerSingleton<StorageDownloader>(
      StorageDownloader(fetcher, prefix: ''),
    );
    container.registerSingleton<LocalImageStore>(imageStore);
  });

  tearDown(() async {
    container.unregister<ImageCache>();
    container.unregister<StorageDownloader>();
    container.unregister<LocalImageStore>();
    await imageStore.close();
  });

  /// Mounts the widget and settles it with plain pumps.
  ///
  /// No [WidgetTester.runAsync] here: the widget starts its load from a
  /// post-frame callback, which runAsync keeps from ever firing.
  Future<void> pumpImage(
    WidgetTester tester, {
    required String path,
    Widget? placeholder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 24,
            height: 24,
            child: CachedApiImage(
              path: path,
              width: 24,
              height: 24,
              mode: ImageMode.cover,
              format: 'webp',
              placeholder: placeholder,
              errorBuilder: (context, error, stackTrace) =>
                  const Text('failed', textDirection: TextDirection.ltr),
            ),
          ),
        ),
      ),
    );

    for (var round = 0; round < 30; round++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  group('CachedApiImage', () {
    testWidgets('renders a downloaded image', (tester) async {
      await pumpImage(tester, path: 'avatars/a.png');

      expect(find.text('failed'), findsNothing);
      expect(adapter.calls, ['GET /storage/download/avatars/a.png']);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('serves the mirrored bytes when the server is unreachable', (
      tester,
    ) async {
      // What the image mirror stored: the variant the model declares, not the
      // rendition this widget asks for.
      await imageStore.putVariant(
        'avatars/a.png',
        '256x256|cover|webp',
        _png,
        width: 256,
        height: 256,
      );

      adapter.offline = true;
      await pumpImage(tester, path: 'avatars/a.png');

      // The widget used to go straight to the downloader and show its error
      // builder, leaving mirrored images unusable offline.
      expect(find.text('failed'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('shows the error builder with nothing mirrored', (
      tester,
    ) async {
      adapter.offline = true;
      await pumpImage(tester, path: 'avatars/missing.png');

      expect(find.text('failed'), findsOneWidget);
    });

    testWidgets('downloads one rendition across a resize animation', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      // A widget sized by its parent is measured again at every frame: without
      // rounding, the sizes below are eleven renditions to download and eleven
      // variants for the server to encode from the original file.
      for (var side = 80.0; side >= 74.0; side -= 0.6) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: const CachedApiImage(
                    path: 'recipes/a.png',
                    mode: ImageMode.cover,
                    format: 'webp',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      for (var round = 0; round < 30; round++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(adapter.renditions, ['256x256']);
    });

    testWidgets(
      'renders a file awaiting its upload without asking the server',
      (tester) async {
        await imageStore.putVariant('local://0001-0000', 'origin', _png);

        await pumpImage(tester, path: 'local://0001-0000');

        expect(find.text('failed'), findsNothing);
        expect(adapter.calls, isEmpty);
        expect(find.byType(Image), findsOneWidget);
      },
    );
  });
}
