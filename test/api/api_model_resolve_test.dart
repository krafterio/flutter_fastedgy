/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _FakeMetadataProvider implements MetadataProvider {
  final Map<String, MetadataModel> _map;

  _FakeMetadataProvider(this._map);

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
  void setPrefix(String? newPrefix) {}
}

MetadataModel _meta(String name, String apiName) => MetadataModel(
  name: name,
  apiName: apiName,
  label: name,
  labelPlural: name,
  searchable: false,
  sortable: false,
  fields: const {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    if (!hasService<Fetcher>()) {
      container.registerSingleton<Fetcher>(
        Fetcher.create(
          dio: Dio(BaseOptions(baseUrl: 'http://localhost')),
          bus: getService<Bus>(),
          enableAuth: false,
          enableTimezone: false,
          enableRefreshToken: false,
          enableConnectionRetry: false,
          enableLogging: false,
          enableErrorTransform: false,
        ),
      );
    }

    if (!hasService<MetadataProvider>()) {
      container.registerSingleton<MetadataProvider>(
        _FakeMetadataProvider({'thing': _meta('thing', 'things')}),
      );
    }
  });

  test(
    'resolvePath appends the metadata api_name to the prefix and memoizes',
    () async {
      final api = GenericApiModel('/{workspace}', modelName: 'thing');

      expect(await api.resolvePath(), '/{workspace}/things');
      expect(api.resolvedBasePath, '/{workspace}/things');
    },
  );

  test('resolvePath with an empty prefix builds an absolute path', () async {
    final api = GenericApiModel('', modelName: 'thing');

    expect(await api.resolvePath(), '/things');
  });

  test('resolvePath without modelName returns basePath unchanged', () async {
    final api = GenericApiModel('/items');

    expect(await api.resolvePath(), '/items');
    expect(api.resolvedBasePath, '/items');
  });

  test('metadata resolves by modelName', () async {
    final api = GenericApiModel('/{workspace}', modelName: 'thing');

    expect((await api.metadata())?.apiName, 'things');
  });
}
