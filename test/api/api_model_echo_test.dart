/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _PathOnlyThingApi extends ApiModel<_Thing> {
  _PathOnlyThingApi({required Fetcher fetcher})
    : super('/things', fetcher: fetcher);

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

class _Auth implements AuthProvider<dynamic> {
  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<String?> getValidatedAccessToken() async => 'a-token';

  @override
  Future<String?> getAccessToken() async => 'a-token';

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<bool> refreshToken() async => true;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Object?> frames;
  late RealtimeSocket socket;
  late List<ResourceChangedEvent> heard;
  late StreamSubscription<ResourceChangedEvent> listening;

  void receive(Map<String, dynamic> frame) => frames.add(jsonEncode(frame));

  Fetcher fetcherWithEcho() => createMockFetcher(
    (request) async {
      if (request.method == 'DELETE') {
        receive({
          'type': 'thing.deleted',
          'data': {'id': 7},
          'origin': request.headers[originHeader],
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        return const MockResponse.empty();
      }

      return const MockResponse.json({'id': 7, 'name': 'Krafter'});
    },
    enableAuth: false,
    enableTimezone: false,
    enableRefreshToken: false,
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  setUp(() async {
    initializeContainer();
    final bus = Bus();
    container.registerSingleton<Bus>(bus);
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

    frames = StreamController<Object?>();
    socket = RealtimeSocket(
      url: Uri.parse('ws://mock.test/api/ws'),
      connector: (url, headers) async => RealtimeConnection(
        messages: frames.stream,
        send: (_) {},
        close: () async {},
      ),
      online: const Stream<bool>.empty(),
      bus: bus,
      auth: _Auth(),
    );
    container.registerSingleton<RealtimeSocket>(socket);
    await socket.start();
    receive({'type': 'auth_success', 'data': {}});
    await settle();

    heard = [];
    listening = bus.on<ResourceChangedEvent>().listen(heard.add);
  });

  tearDown(() async {
    await listening.cancel();
    await socket.dispose();
    await frames.close();
    container.reset();
  });

  test(
    'an api that names no model knows the name once it has written',
    () async {
      final api = _PathOnlyThingApi(fetcher: fetcherWithEcho());

      expect(api.eventModelName, isNull);

      await api.delete(7);

      expect(api.eventModelName, 'thing');
    },
  );

  test('a delete from a fresh api that names no model drops its own echo, '
      'and the holders hear it once its caller is served', () async {
    final record = ApiRecord<_Thing>(
      _PathOnlyThingApi(fetcher: fetcherWithEcho()),
    );
    addTearDown(record.dispose);
    await record.load(7);
    await settle();

    await _PathOnlyThingApi(fetcher: fetcherWithEcho()).delete(7);

    expect(
      record.isDeleted,
      isFalse,
      reason:
          'the echo of its own delete would close the screen before the '
          'caller closes it, and the caller then closes the one underneath',
    );

    await settle();

    expect(record.isDeleted, isTrue);
    expect(
      heard.where((event) => event.type == ResourceChangeType.deleted),
      hasLength(1),
      reason: 'the delete is heard once, from the api that made it',
    );
  });

  test('the delete of another client still reaches the holders', () async {
    final record = ApiRecord<_Thing>(
      _PathOnlyThingApi(fetcher: fetcherWithEcho()),
    );
    addTearDown(record.dispose);
    await record.load(7);
    await settle();

    receive({
      'type': 'thing.deleted',
      'data': {'id': 7},
      'origin': 'another-device.1',
    });
    await settle();

    expect(record.isDeleted, isTrue);
  });
}
