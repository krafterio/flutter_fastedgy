/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _Membership extends BaseModel<_Membership> {
  _Membership(super.data);
}

class _MembershipApi extends ApiModel<_Membership> {
  _MembershipApi({required Fetcher fetcher})
    : super('/workspace_users', fetcher: fetcher);

  @override
  _Membership fromJson(Map<String, dynamic> json) => _Membership(json);
}

class _UnknownApi extends ApiModel<_Membership> {
  _UnknownApi({required Fetcher fetcher})
    : super('/unknown_things', fetcher: fetcher);
}

class _MockMetadataProvider implements MetadataProvider {
  final Map<String, MetadataModel> metadatas;

  _MockMetadataProvider(this.metadatas);

  @override
  Future<void> fetchMetadatas() async {}

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => metadatas;

  @override
  Future<MetadataModel?> getMetadata(String modelName) async =>
      metadatas[modelName];

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

  late Fetcher fetcher;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    fetcher = Fetcher.create(
      dio: Dio(BaseOptions(baseUrl: 'http://localhost')),
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
      enableErrorTransform: false,
    );

    container.registerSingleton<MetadataProvider>(
      _MockMetadataProvider({
        'workspace_user': const MetadataModel(
          name: 'workspace_user',
          apiName: 'workspace_users',
          label: 'Workspace user',
          labelPlural: 'Workspace users',
          searchable: false,
          sortable: false,
          fields: {
            'role': MetadataField(
              name: 'role',
              label: 'Role',
              type: 'choice',
              readonly: false,
              required: false,
              searchable: false,
              extra: false,
              filterOperators: [],
              choices: {'ADMIN': 'Admin', 'MEMBER': 'Member'},
            ),
          },
        ),
      }),
    );
  });

  group('ApiModel.metadata', () {
    test('resolves the model metadata from the API name', () async {
      final api = _MembershipApi(fetcher: fetcher);

      final metadata = await api.metadata();

      expect(metadata?.name, 'workspace_user');
      expect(metadata?.apiName, 'workspace_users');
    });

    test('exposes choice values and labels through metadataField', () async {
      final api = _MembershipApi(fetcher: fetcher);

      final role = await api.metadataField('role');

      expect(role?.choices, {'ADMIN': 'Admin', 'MEMBER': 'Member'});
      expect(role?.choiceLabel('ADMIN'), 'Admin');
      expect(role?.choiceLabel('unknown'), 'unknown');
    });

    test('returns null for an unknown model', () async {
      final api = _UnknownApi(fetcher: fetcher);

      expect(await api.metadata(), isNull);
      expect(await api.metadataField('role'), isNull);
    });
  });
}
