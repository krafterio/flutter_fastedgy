/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';

class _MockMetadataProvider implements MetadataProvider {
  static const _attachment = MetadataModel(
    name: 'attachment',
    apiName: 'attachments',
    label: 'Attachment',
    labelPlural: 'Attachments',
    searchable: false,
    sortable: false,
    synchronizable: true,
    synchronizableMode: 'partial',
    fields: {},
  );

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => {
    'attachment': _attachment,
  };

  @override
  Future<MetadataModel?> getMetadata(String name) async =>
      name == 'attachment' ? _attachment : null;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> paths;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    paths = [];
    container.registerSingleton<MetadataProvider>(_MockMetadataProvider());
    container.registerSingleton<Fetcher>(
      createMockFetcher(
        (request) {
          paths.add(request.path);

          return const MockResponse.json({
            'items': [
              {
                'id': 7,
                'name': 'spec',
                'extension': 'pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 2048,
              },
            ],
            'total': 1,
            'limit': 25,
            'offset': 0,
            'total_pages': 1,
          });
        },
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  tearDown(() => container.reset());

  group('AttachmentApi', () {
    test('reads its records as typed attachments', () async {
      final api = AttachmentApi('/acme');

      // Without its own fromJson the inherited default casts a DynamicSchema to
      // Attachment, which no value can satisfy: every read threw.
      final result = await api.list();

      expect(result.items, hasLength(1));
      expect(result.items.single.filename, 'spec.pdf');
      expect(result.items.single.isDocument, isTrue);
    });

    test('keeps the resource path it had before naming its model', () async {
      await AttachmentApi('/acme').list();

      // The model name earns it a replicated table; the URL still comes from the
      // metadata api_name, so it must not have moved.
      expect(paths.single, '/acme/attachments');
    });
  });
}
