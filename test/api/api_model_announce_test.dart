/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi({required Fetcher fetcher})
    : super('', modelName: 'thing', apiName: 'things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

/// The shape of the offline engine: it announces the write as soon as the
/// server answered, then writes the local mirror before handing the call back.
class _MirroringEngine<T extends BaseModel<T>> extends ApiModelEngine<T> {
  _MirroringEngine(super.owner);

  @override
  Future<void> delete(Object id, {ApiParams? params}) async {
    await super.delete(id, params: params);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _MirroringEngineProvider implements ApiModelEngineProvider {
  const _MirroringEngineProvider();

  @override
  ApiModelEngine<T> create<T extends BaseModel<T>>(ApiModel<T> owner) =>
      _MirroringEngine<T>(owner);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ThingApi api;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    if (!hasService<MetadataProvider>()) {
      container.registerSingleton<MetadataProvider>(
        FakeMetadataProvider({
          'thing': metaModel(
            'thing',
            apiName: 'things',
            mode: 'full',
            fields: {'id': metaField('id', type: 'integer', readonly: true)},
          ),
        }),
      );
    }

    if (!hasService<ApiModelEngineProvider>()) {
      container.registerSingleton<ApiModelEngineProvider>(
        const _MirroringEngineProvider(),
      );
    }

    api = _ThingApi(
      fetcher: createMockFetcher(
        (_) => const MockResponse.json({'id': 7, 'name': 'Krafter'}),
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
      ),
    );
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'a delete reaches the holders once its caller has been served',
    () async {
      final record = ApiRecord<_Thing>(api);

      addTearDown(record.dispose);
      await record.load(7);

      await api.delete(7);

      expect(
        record.isDeleted,
        isFalse,
        reason:
            'a screen deleting the record it shows acts before it is told the '
            'record is gone, or it closes twice',
      );

      await settle();

      expect(record.isDeleted, isTrue);
    },
  );

  test('an announcement outside a write is fired on the spot', () async {
    final heard = <ResourceChangedEvent>[];
    final subscription = getService<Bus>().on<ResourceChangedEvent>().listen(
      heard.add,
    );

    addTearDown(subscription.cancel);
    api.notifyChanged(ResourceChangeType.updated, 7);
    await settle();

    expect(heard.single.type, ResourceChangeType.updated);
  });
}
