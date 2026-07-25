/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
// Both Flutter and flutter_fastedgy export an ImageCache; only the latter is
// the service the provider resolves.
import 'package:flutter/material.dart' hide ImageCache;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// Smallest decodable PNG (1×1, transparent): the provider hands its bytes to
/// Flutter's real decoder, so a stub payload would fail for the wrong reason.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  int status = 200;
  final List<String> calls = [];
  Uint8List bytes = Uint8List(0);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');

    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    if (status >= 400) {
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: status),
        type: DioExceptionType.badResponse,
      );
    }

    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Marks a resolution that never produced a frame nor an error.
class _NeverSettled {
  const _NeverSettled();

  @override
  String toString() => 'the image stream never settled';
}

/// Bounded number of settle rounds, so a provider that never answers fails the
/// test instead of hanging the suite.
const _settleRounds = 40;

/// Resolve [provider] and report the outcome: null on success, the error
/// otherwise, [_NeverSettled] when nothing came back in time.
///
/// An ImageStream cannot be awaited directly, so its listener is bridged onto a
/// Completer. Settling one needs both halves of the test clock, alternated:
/// - the fetch and the decode are real async work, which only progresses inside
///   [WidgetTester.runAsync];
/// - handing the decoded frame to the listeners is scheduled as a frame
///   callback, which only progresses on [WidgetTester.pump].
///
/// Reading `isCompleted` rather than awaiting the future is deliberate: the
/// listener fires in the test's fake-clock zone, so the future's continuation
/// would never run while waiting inside the real one.
Future<Object?> _resolveOutcome(
  WidgetTester tester,
  ImageProvider provider,
) async {
  final outcome = Completer<Object?>();
  final listener = ImageStreamListener(
    (image, _) {
      if (!outcome.isCompleted) {
        outcome.complete(null);
      }
    },
    onError: (error, _) {
      if (!outcome.isCompleted) {
        outcome.complete(error);
      }
    },
  );

  late final ImageStream stream;

  // Started inside runAsync so the HTTP round-trip lives in the real zone: from
  // the fake-clock one its timers would never fire.
  await tester.runAsync(() async {
    stream = provider.resolve(ImageConfiguration.empty);
    stream.addListener(listener);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  for (var round = 0; round < _settleRounds && !outcome.isCompleted; round++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }

  stream.removeListener(listener);

  if (!outcome.isCompleted) {
    outcome.complete(const _NeverSettled());
  }

  return outcome.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late DriftLocalImageStore imageStore;
  late BuildContext context;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    adapter = _ScriptedAdapter()..bytes = _png;

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

    // A fresh cache per test: a memoized image would answer for the next one.
    container.registerSingleton<ImageCache>(ImageCache(getService<Bus>()));

    // Flutter keeps its own global image cache, keyed by the provider's
    // identity — and it outlives a test. Without this, a provider already
    // resolved by an earlier test is served from memory and the code under test
    // never runs.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  CachedApiImageProvider provider(String path) => CachedApiImageProvider(
    context: context,
    path: path,
    width: 8,
    height: 8,
    autoCalculatePhysicalDimensions: false,
  );

  group('CachedApiImageProvider', () {
    testWidgets('downloads a stored path and mirrors it', (tester) async {
      await mount(tester);

      expect(await _resolveOutcome(tester, provider('avatars/a.png')), isNull);
      expect(adapter.calls, ['GET /storage/download/avatars/a.png']);

      // Kept for the next offline read.
      expect(await imageStore.getBestVariant('avatars/a.png'), isNotNull);
    });

    testWidgets('serves the mirrored bytes when the server is unreachable', (
      tester,
    ) async {
      await mount(tester);
      await _resolveOutcome(tester, provider('avatars/a.png'));

      adapter.offline = true;
      container.unregister<ImageCache>();
      container.registerSingleton<ImageCache>(ImageCache(getService<Bus>()));

      expect(await _resolveOutcome(tester, provider('avatars/a.png')), isNull);
    });

    testWidgets('falls back to a differently sized mirrored variant', (
      tester,
    ) async {
      await mount(tester);

      // What the image mirror prefetches: the variants the model declares
      // (`SyncImageField(variants: [ImageVariant(width: 256, height: 256)])`),
      // which is not the rendition a widget asks for — that one comes from its
      // own logical size times the device pixel ratio.
      await imageStore.putVariant(
        'avatars/a.png',
        '256x256|cover|webp',
        _png,
        width: 256,
        height: 256,
      );

      adapter.offline = true;

      // The exact key misses, so the most faithful stored one has to answer:
      // otherwise every mirrored image is unusable offline, the widget never
      // asking for the size the mirror stored.
      expect(await _resolveOutcome(tester, provider('avatars/a.png')), isNull);
      expect(adapter.calls, ['GET /storage/download/avatars/a.png']);
    });

    testWidgets('fails on a server error with nothing mirrored', (
      tester,
    ) async {
      await mount(tester);
      adapter.status = 404;

      expect(
        await _resolveOutcome(tester, provider('avatars/missing.png')),
        isNotNull,
      );
    });

    testWidgets('never asks the server for a pending upload', (tester) async {
      await mount(tester);

      // What a file buffered offline looks like: bytes local, no server path.
      await imageStore.putVariant('local://0001-0000', 'origin', _png);

      expect(
        await _resolveOutcome(tester, provider('local://0001-0000')),
        isNull,
      );

      // The server knows no such path: asking would 404, and the offline
      // fallback does not cover that status — the image would stay blank.
      expect(adapter.calls, isEmpty);
    });

    testWidgets('serves a pending upload while connected', (tester) async {
      await mount(tester);
      await imageStore.putVariant('local://0001-0000', 'origin', _png);

      // Reachable server, upload not replayed yet: still served locally.
      adapter.offline = false;
      adapter.status = 404;

      expect(
        await _resolveOutcome(tester, provider('local://0001-0000')),
        isNull,
      );
      expect(adapter.calls, isEmpty);
    });

    testWidgets('fails when a pending upload has no local bytes', (
      tester,
    ) async {
      await mount(tester);

      final outcome = await _resolveOutcome(
        tester,
        provider('local://0001-0000'),
      );

      expect(outcome, isA<StateError>());
      expect(adapter.calls, isEmpty);
    });

    testWidgets('equality keys on the path and the rendition', (tester) async {
      await mount(tester);

      expect(provider('a.png'), provider('a.png'));
      expect(provider('a.png').hashCode, provider('a.png').hashCode);
      expect(provider('a.png'), isNot(provider('b.png')));
      expect(
        provider('a.png'),
        isNot(
          CachedApiImageProvider(
            context: context,
            path: 'a.png',
            width: 8,
            height: 8,
            format: 'png',
            autoCalculatePhysicalDimensions: false,
          ),
        ),
      );
    });
  });
}
