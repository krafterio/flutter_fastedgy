/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Metadata read under a workspace the test moves.
class _Metadatas implements MetadataProvider {
  String current = '/h/acme';

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => const {};

  @override
  Future<MetadataModel?> getMetadata(String name) async => null;

  @override
  Future<void> fetchMetadatas() async {}

  @override
  bool get loading => false;

  @override
  dynamic get error => null;

  @override
  String? get prefix => null;

  @override
  String get scope => current;

  @override
  void setPrefix(String? newPrefix) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Metadatas metadatas;
  late List<String> asked;
  late SyncStateProbe probe;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    metadatas = _Metadatas();
    container.registerSingleton<MetadataProvider>(metadatas);
    asked = [];
    probe = SyncStateProbe(
      fetcher: createMockFetcher((request) {
        asked.add(request.path);

        return const MockResponse.json({
          'items': [
            {'model': 'item', 'count': 1},
          ],
        });
      }, enableAuth: false),
    );
  });

  tearDown(container.reset);

  test('never serves one workspace the states of another', () async {
    await probe.fetch();
    metadatas.current = '/h/studio';
    await probe.fetch();
    metadatas.current = '/h/acme';
    await probe.fetch();

    expect(asked, [
      '/h/acme/dataset/sync-state',
      '/h/studio/dataset/sync-state',
    ]);
  });
}
