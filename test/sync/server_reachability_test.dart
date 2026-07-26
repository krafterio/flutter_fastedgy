/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// A transport that either answers, refuses, or is not there at all.
class _ScriptedAdapter implements HttpClientAdapter {
  bool unreachable = false;
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (unreachable) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'no route to host',
      );
    }

    return ResponseBody.fromString(
      '{"detail": "scripted"}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedAdapter adapter;
  late Fetcher fetcher;
  late SyncStatus status;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    // Online, as the connectivity stream reports it on a device whose wifi is up.
    status = SyncStatus(getService<Bus>(), online: true);
    container.registerSingleton<SyncStatus>(status);

    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter;
    fetcher = Fetcher.create(
      dio: dio,
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
    );
  });

  tearDown(() => container.unregister<SyncStatus>());

  Future<void> request() async {
    try {
      await fetcher.get('/anything');
    } catch (_) {}
  }

  group('server reachability from the requests', () {
    test('an unanswered request marks the server unreachable', () async {
      adapter.unreachable = true;

      await request();

      // The bug this fixes: the device is online, so anything gating on
      // connectivity alone offered actions that could not be delivered.
      expect(status.online, isTrue);
      expect(status.serverAnswering, isFalse);
      expect(status.reachable, isFalse);
      expect(SyncStatus.currentlyReachable, isFalse);
    });

    test('an answer brings it back', () async {
      adapter.unreachable = true;
      await request();

      adapter.unreachable = false;
      await request();

      expect(status.reachable, isTrue);
    });

    test('a refusal is the server working', () async {
      adapter.status = 404;

      await request();

      // A 404 came from the server: it is there, it just said no.
      expect(status.reachable, isTrue);
    });

    test('a maintenance window counts as unreachable', () async {
      adapter.status = 503;

      await request();

      // Nothing was processed, so it degrades like a lost connection.
      expect(status.reachable, isFalse);
    });

    test('nothing to report to is not an error', () async {
      container.unregister<SyncStatus>();
      adapter.unreachable = true;

      await request();

      // A build without the offline write path has no SyncStatus, and reads as
      // reachable rather than crashing on a missing service.
      expect(SyncStatus.currentlyReachable, isTrue);

      container.registerSingleton<SyncStatus>(status);
    });
  });
}
