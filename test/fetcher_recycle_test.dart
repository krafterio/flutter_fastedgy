/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  setUp(() {
    initializeContainer();
    container.registerSingleton<Bus>(Bus());
  });

  tearDown(() {
    container.reset();
  });

  group('Fetcher.recycleConnections', () {
    test('swaps in a fresh IO adapter', () {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
      final fetcher = Fetcher.create(
        dio: dio,
        bus: getService<Bus>(),
        enableLogging: false,
      );

      final before = dio.httpClientAdapter;
      expect(before, isA<IOHttpClientAdapter>());

      fetcher.recycleConnections();

      final after = dio.httpClientAdapter;
      expect(after, isA<IOHttpClientAdapter>());
      expect(identical(before, after), isFalse);
    });
  });
}
