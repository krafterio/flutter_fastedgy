/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

@Timeout(Duration(seconds: 10))
library;

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi(super.basePath, {super.modelName, super.fetcher});
}

class _Auth implements AuthProvider<dynamic> {
  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<String?> getValidatedAccessToken() async => null;

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<bool> refreshToken() async => false;

  @override
  Future<AuthResult<dynamic>> login(String username, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthResult<dynamic>> register(Map<String, dynamic> userData) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<dynamic> getCurrentUser() async => null;
}

class _Socket extends RealtimeSocket {
  _Socket(Bus bus) : super(bus: bus, auth: _Auth());

  final calls = <String>[];

  @override
  void subscribe(String model, [Object? id]) =>
      calls.add('+${channelOf(model, id)}');

  @override
  void unsubscribe(String model, [Object? id]) =>
      calls.add('-${channelOf(model, id)}');
}

class _Metadatas implements MetadataProvider {
  static const _thing = MetadataModel(
    name: 'thing',
    apiName: 'things',
    label: 'Thing',
    labelPlural: 'Things',
    searchable: false,
    sortable: false,
    fields: {},
  );

  @override
  Future<void> fetchMetadatas() async {}

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => {'thing': _thing};

  @override
  Future<MetadataModel?> getMetadata(String modelName) async =>
      modelName == 'thing' ? _thing : null;

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

  late Bus bus;
  late Fetcher fetcher;
  late _ThingApi api;
  late List<ResourceChangedEvent> heard;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    bus = getService<Bus>();
    heard = [];
    fetcher = createMockFetcher(
      (_) => const MockResponse.json({}),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );
    api = _ThingApi('/{workspace}', modelName: 'thing', fetcher: fetcher);
  });

  tearDown(() async {
    if (hasService<RealtimeSocket>()) {
      await container.unregister<RealtimeSocket>();
    }
  });

  _Socket socket() {
    final socket = _Socket(bus);

    container.registerSingleton<RealtimeSocket>(socket);

    return socket;
  }

  ResourceWatch watch({
    ApiModel<dynamic>? on,
    Object? id,
    bool Function(ResourceChangedEvent event)? where,
    Duration refreshDelay = Duration.zero,
  }) {
    final watch = watchResource(
      on ?? api,
      heard.add,
      id: id,
      where: where,
      refreshDelay: refreshDelay,
    );

    addTearDown(watch.cancel);

    return watch;
  }

  Future<void> fire(Object event) async {
    bus.fire(event);
    await Future<void>.delayed(Duration.zero);
  }

  test('hears a change of the model it watches', () async {
    watch();
    await fire(
      const ResourceChangedEvent(
        null,
        model: 'thing',
        type: ResourceChangeType.updated,
        id: 7,
      ),
    );

    expect(heard.single.id, 7);
  });

  test('leaves another model alone', () async {
    watch();
    await fire(const ResourceChangedEvent(null, model: 'other', id: 7));

    expect(heard, isEmpty);
  });

  test('leaves another record alone when it watches one', () async {
    watch(id: 7);
    await fire(const ResourceChangedEvent(null, model: 'thing', id: 9));
    await fire(const ResourceChangedEvent(null, model: 'thing', id: '7'));

    expect(heard, hasLength(1));
  });

  test('hears an event that names no record', () async {
    watch(id: 7);
    await fire(const ResourceChangedEvent(null, model: 'thing'));

    expect(heard, hasLength(1));
  });

  test('follows the record it is moved to, channel included, and drops a call pending for the old one', () async {
    final spy = socket();
    final one = watch(id: 7, refreshDelay: const Duration(milliseconds: 20));

    await fire(const ResourceChangedEvent(null, model: 'thing', id: 7));
    one.id = 9;
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(heard, isEmpty);
    expect(spy.calls, ['+thing:7', '-thing:7', '+thing:9']);
  });

  test('collapses a burst into one call', () async {
    watch(refreshDelay: const Duration(milliseconds: 20));

    for (var i = 0; i < 5; i++) {
      bus.fire(
        const ResourceChangedEvent(
          null,
          model: 'thing',
          type: ResourceChangeType.updated,
        ),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(heard, hasLength(1));
  });

  test(
    'asks the holder to read again when the socket comes back, without waiting',
    () async {
      watch(refreshDelay: const Duration(seconds: 5));
      await fire(const ResourcesStaleEvent());

      expect(heard.single.type, isNull);
      expect(heard.single.id, isNull);
      expect(heard.single.model, 'thing');
    },
  );

  test('subscribes the socket to what it watches, and lets go once however often it is cancelled', () async {
    final spy = socket();

    watch(id: 7)
      ..cancel()
      ..cancel();

    expect(spy.calls, ['+thing:7', '-thing:7']);
  });

  test('subscribes nothing without a model name, or without a socket', () {
    watch().cancel();

    final spy = socket();

    watch(on: _ThingApi('/things', fetcher: fetcher)).cancel();

    expect(spy.calls, isEmpty);
  });

  group('a model declared by its path', () {
    setUp(() => container.registerSingleton<MetadataProvider>(_Metadatas()));

    tearDown(() => container.unregister<MetadataProvider>());

    test('subscribes and hears under the name its metadata give', () async {
      final spy = socket();

      watch(on: _ThingApi('/things', fetcher: fetcher), id: 3);
      await Future<void>.delayed(Duration.zero);
      await fire(const ResourceChangedEvent(null, model: 'thing', id: 3));

      expect(spy.calls, ['+thing:3']);
      expect(heard, hasLength(1));
    });

    test('subscribes only the record it moved to before being named', () async {
      final spy = socket();

      watch(on: _ThingApi('/things', fetcher: fetcher), id: 3).id = 4;
      await Future<void>.delayed(Duration.zero);

      expect(spy.calls, ['+thing:4']);
    });

    test('subscribes nothing once cancelled before being named', () async {
      final spy = socket();

      watch(on: _ThingApi('/things', fetcher: fetcher)).cancel();
      await Future<void>.delayed(Duration.zero);

      expect(spy.calls, isEmpty);
    });
  });

  test('hears an event fired with a path alone', () async {
    watch(on: _ThingApi('/things', fetcher: fetcher));
    await fire(
      const ResourceChangedEvent('/things', type: ResourceChangeType.created),
    );

    expect(heard, hasLength(1));
  });

  test(
    'leaves alone what where refuses, and lets through a stale event',
    () async {
      watch(where: (event) => event.mayBeAbout({'flow': 42}));
      await fire(
        const ResourceChangedEvent(null, model: 'thing', data: {'flow': 7}),
      );

      expect(heard, isEmpty);

      await fire(
        const ResourceChangedEvent(null, model: 'thing', data: {'flow': 42}),
      );
      await fire(const ResourcesStaleEvent());

      expect(heard, hasLength(2));
    },
  );

  test(
    'delivers nothing while inactive, and one call once active again',
    () async {
      final one = watch()..active = false;

      await fire(const ResourceChangedEvent(null, model: 'thing', id: 7));
      await fire(const ResourceChangedEvent(null, model: 'thing', id: 8));
      await fire(const ResourcesStaleEvent());

      expect(heard, isEmpty);

      one.active = true;

      expect(heard.single.type, isNull);
    },
  );

  test('owes nothing when nothing came while it was inactive', () {
    watch()
      ..active = false
      ..active = true;

    expect(heard, isEmpty);
  });
}
