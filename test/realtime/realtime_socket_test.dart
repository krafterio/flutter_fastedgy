/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth implements AuthProvider<dynamic> {
  bool signedIn = true;
  String? token = 'a-token';
  Object refresh = true;
  int refreshes = 0;

  @override
  Future<bool> isAuthenticated() async => signedIn;

  @override
  Future<String?> getValidatedAccessToken() async => token;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<bool> refreshToken() async {
    refreshes++;

    final answer = refresh;

    if (answer is bool) {
      return answer;
    }

    throw answer;
  }

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

class _Link {
  _Link(this.url, this.headers);

  final Uri url;
  final Map<String, dynamic> headers;
  final sent = <Map<String, dynamic>>[];
  final _frames = StreamController<Object?>();
  bool closed = false;

  late final connection = RealtimeConnection(
    messages: _frames.stream,
    send: (frame) => sent.add(jsonDecode(frame) as Map<String, dynamic>),
    close: () async {
      closed = true;
      unawaited(_frames.close());
    },
  );

  void receive(Map<String, dynamic> frame) => _frames.add(jsonEncode(frame));

  void drop() => unawaited(_frames.close());

  List<Map<String, dynamic>> framesOf(String type) =>
      sent.where((frame) => frame['type'] == type).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Bus bus;
  late _Auth auth;
  late List<_Link> links;
  late StreamController<bool> online;
  late List<Object> heard;
  late DateTime now;

  setUp(() {
    initializeContainer();
    bus = Bus();
    auth = _Auth();
    links = [];
    online = StreamController<bool>.broadcast();
    heard = [];
    now = DateTime(2026, 9, 13, 12);
    bus.on<ResourceChangedEvent>().listen(heard.add);
    bus.on<RealtimeEvent>().listen(heard.add);
    bus.on<ResourcesStaleEvent>().listen(heard.add);
  });

  RealtimeSocket socketOf({RealtimeConnector? connector}) => RealtimeSocket(
    url: Uri.parse('ws://mock.test/api/ws'),
    connector:
        connector ??
        (url, headers) async {
          final link = _Link(url, headers);

          links.add(link);

          return link.connection;
        },
    online: online.stream,
    bus: bus,
    auth: auth,
  );

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  // On a clock the test moves by hand: an absence is counted on the clock, the
  // timers of a suspended process standing still.
  void testSocket(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(
    description,
    (tester) => withClock(Clock(() => now), () => body(tester)),
    timeout: const Timeout(Duration(seconds: 5)),
  );

  Future<_Link> connect(WidgetTester tester, RealtimeSocket socket) async {
    await socket.start();
    await flush(tester);
    links.last.receive({'type': 'auth_success', 'data': {}});
    await flush(tester);

    return links.last;
  }

  Future<void> reopen(WidgetTester tester, Duration after) async {
    await flush(tester);
    await tester.pump(after);
    await flush(tester);
  }

  Iterable<ResourceChangedEvent> changes() =>
      heard.whereType<ResourceChangedEvent>();

  int stales() => heard.whereType<ResourcesStaleEvent>().length;

  testSocket('authenticates itself with the first frame it sends', (
    tester,
  ) async {
    final socket = socketOf()..watch('krafter');

    await socket.start();
    await flush(tester);

    expect(links.single.sent.first, {
      'type': 'authenticate',
      'data': {'token': 'a-token', 'scope': 'krafter'},
    });

    await socket.dispose();
  });

  test('opens against the api path, over the websocket scheme', () {
    expect(
      RealtimeSocket.urlOf('http://localhost:8000/api'),
      Uri.parse('ws://localhost:8000/api/ws'),
    );
    expect(
      RealtimeSocket.urlOf('https://app.kascade.io/api/'),
      Uri.parse('wss://app.kascade.io/api/ws'),
    );
  });

  testSocket('carries a server announcement onto the bus', (tester) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    link.receive({
      'type': 'flow_message.created',
      'data': {'model': 'flow_message', 'id': 4, 'flow': 9},
      'origin': 'another-app',
    });
    await flush(tester);

    final change = changes().single;

    expect(change.model, 'flow_message');
    expect(change.type, ResourceChangeType.created);
    expect(change.id, 4);
    expect(change.data, {'model': 'flow_message', 'id': 4, 'flow': 9});
    expect(change.origin, 'another-app');
    expect(change.basePath, isNull);
    expect(change.announced, isTrue);

    await socket.dispose();
  });

  testSocket('passes on what an update moved, and a payload left behind', (
    tester,
  ) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    link
      ..receive({
        'type': 'flow.updated',
        'data': {'id': 7},
        'changed': ['name'],
      })
      ..receive({'type': 'flow.updated', 'data': null, 'truncated': true});
    await flush(tester);

    expect(changes().first.fields, {'name'});
    expect(changes().last.truncated, isTrue);
    expect(changes().last.id, isNull);

    await socket.dispose();
  });

  testSocket('leaves alone the echo it expected, once', (tester) async {
    final socket = socketOf();
    final link = await connect(tester, socket);
    final origin = requestOrigin();

    socket.expect(origin, 'flow', '7');
    link
      ..receive({
        'type': 'flow.updated',
        'data': {'id': 7},
        'origin': origin,
      })
      ..receive({
        'type': 'flow.updated',
        'data': {'id': 7},
        'origin': origin,
      });
    await flush(tester);

    expect(changes(), hasLength(1));
    expect(changes().single.origin, originId);

    await socket.dispose();
  });

  testSocket(
    'hears what a signal wrote on another record while serving an expected request',
    (tester) async {
      final socket = socketOf();
      final link = await connect(tester, socket);
      final origin = requestOrigin();

      socket.expect(origin, 'flow_message');
      link
        ..receive({
          'type': 'flow_message.created',
          'data': {'id': 4},
          'origin': origin,
        })
        ..receive({
          'type': 'flow_subscription.created',
          'data': {'id': 9},
          'origin': origin,
        });
      await flush(tester);

      expect(changes().map((change) => change.model), ['flow_subscription']);

      await socket.dispose();
    },
  );

  testSocket('hears the echo of a write that expected nothing, as its own', (
    tester,
  ) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    link.receive({
      'type': 'flow.updated',
      'data': {'id': 7},
      'origin': originId,
    });
    await flush(tester);

    expect(changes().single.origin, originId);
    expect(changes().single.announced, isTrue);

    await socket.dispose();
  });

  testSocket('never lets an expectation swallow the frame of another request', (
    tester,
  ) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    socket.expect(requestOrigin(), 'notification');
    link.receive({
      'type': 'notification.deleted',
      'data': {'id': 3},
      'origin': requestOrigin(),
    });
    await flush(tester);

    expect(changes(), hasLength(1));

    await socket.dispose();
  });

  testSocket('forgets an expectation no frame answered', (tester) async {
    final socket = socketOf();
    final link = await connect(tester, socket);
    final origin = requestOrigin();

    socket.expect(origin, 'flow', 7);
    now = now.add(const Duration(seconds: 31));
    link.receive({
      'type': 'flow.updated',
      'data': {'id': 7},
      'origin': origin,
    });
    await flush(tester);

    expect(changes(), hasLength(1));

    await socket.dispose();
  });

  testSocket('puts an application event on the bus, never taken for a write', (
    tester,
  ) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    link.receive({
      'type': 'import.finished',
      'data': {'rows': 12},
    });
    await flush(tester);

    final event = heard.whereType<RealtimeEvent>().single;

    expect(event.type, 'import.finished');
    expect(event.data, {'rows': 12});
    expect(changes(), isEmpty);

    await socket.dispose();
  });

  testSocket(
    'tells the server when the application reads another scope, once',
    (tester) async {
      final socket = socketOf()..watch('krafter');
      final link = await connect(tester, socket);

      socket
        ..watch('studio-nord')
        ..watch('studio-nord');

      expect(link.framesOf('watch'), [
        {
          'type': 'watch',
          'data': {'scope': 'studio-nord'},
        },
      ]);

      await socket.dispose();
    },
  );

  testSocket('catches up when the scope changed while it was authenticating', (
    tester,
  ) async {
    final socket = socketOf()..watch('krafter');

    await socket.start();
    await flush(tester);
    socket.watch('studio-nord');
    links.single.receive({'type': 'auth_success', 'data': {}});
    await flush(tester);

    expect(links.single.framesOf('watch'), [
      {
        'type': 'watch',
        'data': {'scope': 'studio-nord'},
      },
    ]);

    await socket.dispose();
  });

  testSocket('says its channels again to the scope it moves to', (
    tester,
  ) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    socket
      ..subscribe('flow')
      ..subscribe('flow', 42)
      ..watch('studio-nord');

    expect(link.sent.last, {
      'type': 'subscribe',
      'data': {
        'channels': ['flow', 'flow:42'],
      },
    });

    await socket.dispose();
  });

  testSocket(
    'asks once for the same channel, and keeps it while one holder still does',
    (tester) async {
      final socket = socketOf();
      final link = await connect(tester, socket);

      socket
        ..subscribe('flow', 42)
        ..subscribe('flow', 42)
        ..unsubscribe('flow', 42);

      expect(link.framesOf('subscribe'), hasLength(1));
      expect(link.framesOf('unsubscribe'), isEmpty);

      socket
        ..unsubscribe('flow', 42)
        ..unsubscribe('flow', 42);

      expect(link.framesOf('unsubscribe'), [
        {
          'type': 'unsubscribe',
          'data': {
            'channels': ['flow:42'],
          },
        },
      ]);

      await socket.dispose();
    },
  );

  testSocket('asks again for a channel let go and taken back', (tester) async {
    final socket = socketOf();
    final link = await connect(tester, socket);

    socket
      ..subscribe('flow')
      ..unsubscribe('flow')
      ..subscribe('flow');

    expect(link.framesOf('subscribe'), hasLength(2));

    await socket.dispose();
  });

  testSocket('says its subscriptions again on a new socket', (tester) async {
    final socket = socketOf();
    final first = await connect(tester, socket);

    socket.subscribe('flow', 42);
    first.drop();
    await reopen(tester, const Duration(seconds: 1));
    links.last.receive({'type': 'auth_success', 'data': {}});
    await flush(tester);

    expect(links, hasLength(2));
    expect(links.last.sent.last, {
      'type': 'subscribe',
      'data': {
        'channels': ['flow:42'],
      },
    });

    await socket.dispose();
  });

  testSocket(
    'tells the holders to read again when it comes back, and not on the first handshake',
    (tester) async {
      final socket = socketOf();
      final first = await connect(tester, socket);

      expect(stales(), 0);

      first.drop();
      await reopen(tester, const Duration(seconds: 1));
      links.last.receive({'type': 'auth_success', 'data': {}});
      await flush(tester);

      expect(stales(), 1);

      await socket.dispose();
    },
  );

  testSocket('reopens a socket that closed on its own, later each time', (
    tester,
  ) async {
    final socket = socketOf();
    final first = await connect(tester, socket);

    first.drop();
    await reopen(tester, const Duration(milliseconds: 999));

    expect(links, hasLength(1));

    await reopen(tester, const Duration(milliseconds: 1));

    expect(links, hasLength(2));

    links.last.drop();
    await reopen(tester, const Duration(milliseconds: 1999));

    expect(links, hasLength(2));

    await reopen(tester, const Duration(milliseconds: 1));

    expect(links, hasLength(3));

    await socket.dispose();
  });

  testSocket(
    'refreshes the token once when refused, and stays closed on a second refusal',
    (tester) async {
      final socket = socketOf();

      await socket.start();
      await flush(tester);
      links.single.receive({'type': 'auth_error', 'data': {}});
      await flush(tester);

      expect(auth.refreshes, 1);
      expect(links, hasLength(2));

      links.last.receive({'type': 'auth_error', 'data': {}});
      await reopen(tester, const Duration(minutes: 1));

      expect(auth.refreshes, 1);
      expect(links, hasLength(2));

      await socket.dispose();
    },
  );

  testSocket(
    'takes a refused refresh for a refusal, and an unanswered one for a close',
    (tester) async {
      auth.refresh = UnauthorizedError(message: 'Refused');

      final refused = socketOf();

      await refused.start();
      await flush(tester);
      links.single.receive({'type': 'auth_error', 'data': {}});
      await reopen(tester, const Duration(minutes: 1));

      expect(links, hasLength(1));

      await refused.dispose();

      auth.refresh = NetworkError(message: 'Unreachable');

      final unanswered = socketOf();

      await unanswered.start();
      await flush(tester);
      links.last.receive({'type': 'auth_error', 'data': {}});
      await reopen(tester, const Duration(seconds: 1));

      expect(links, hasLength(3));

      await unanswered.dispose();
    },
  );

  testSocket('opens again when refused and then pointed at another scope', (
    tester,
  ) async {
    auth.refresh = false;

    final socket = socketOf()..watch('not-mine');

    await socket.start();
    await flush(tester);
    links.single.receive({'type': 'auth_error', 'data': {}});
    await flush(tester);

    expect(links, hasLength(1));

    socket.watch('krafter');
    await flush(tester);

    expect(links, hasLength(2));
    expect(links.last.sent.first['data'], {
      'token': 'a-token',
      'scope': 'krafter',
    });

    await socket.dispose();
  });

  testSocket(
    'opens again after a refusal when the app comes back to the foreground',
    (tester) async {
      auth.refresh = false;

      final socket = socketOf();

      await socket.start();
      await flush(tester);
      links.single.receive({'type': 'auth_error', 'data': {}});
      await flush(tester);
      socket.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 2));
      socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush(tester);

      expect(links, hasLength(2));

      await socket.dispose();
    },
  );

  testSocket(
    'closes on sign-out, keeps its channels, and reads again after the next sign-in',
    (tester) async {
      final socket = socketOf();
      final first = await connect(tester, socket);

      socket.subscribe('notification');
      bus.fire(const AuthLogoutEvent());
      await flush(tester);

      expect(first.closed, isTrue);

      bus.fire(const AuthLoggedEvent());
      await flush(tester);
      links.last.receive({'type': 'auth_success', 'data': {}});
      await flush(tester);

      expect(links, hasLength(2));
      expect(links.last.sent.last, {
        'type': 'subscribe',
        'data': {
          'channels': ['notification'],
        },
      });
      expect(stales(), 1);

      await socket.dispose();
    },
  );

  testSocket(
    'never overlaps two openings, and closes what a late one brings back after a sign-out',
    (tester) async {
      final gate = Completer<void>();
      final opened = <_Link>[];
      final socket = socketOf(
        connector: (url, headers) async {
          await gate.future;

          final link = _Link(url, headers);

          opened.add(link);

          return link.connection;
        },
      );

      await socket.start();
      await flush(tester);
      online.add(true);
      bus.fire(const AuthLoggedEvent());
      await flush(tester);
      bus.fire(const AuthLogoutEvent());
      await flush(tester);
      gate.complete();
      await flush(tester);

      expect(opened, hasLength(1));
      expect(opened.single.closed, isTrue);
      expect(opened.single.sent, isEmpty);

      await socket.dispose();
    },
  );

  testSocket('gives up an opening that fails, and tries again later', (
    tester,
  ) async {
    var attempts = 0;
    final socket = socketOf(
      connector: (url, headers) async {
        attempts++;

        throw TimeoutException('The handshake hung');
      },
    );

    await socket.start();
    await flush(tester);

    expect(attempts, 1);

    await reopen(tester, const Duration(seconds: 1));

    expect(attempts, 2);

    await socket.dispose();
  });

  testSocket(
    'closes past the grace in the background, and reopens on resume with a read of everything',
    (tester) async {
      final socket = socketOf();
      final first = await connect(tester, socket);

      socket.didChangeAppLifecycleState(AppLifecycleState.paused);
      await reopen(tester, const Duration(seconds: 20));

      expect(first.closed, isTrue);
      expect(links, hasLength(1));

      now = now.add(const Duration(minutes: 1));
      socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush(tester);
      links.last.receive({'type': 'auth_success', 'data': {}});
      await flush(tester);

      expect(links, hasLength(2));
      expect(stales(), 1);

      await socket.dispose();
    },
  );

  testSocket('keeps its socket through a short absence', (tester) async {
    final socket = socketOf();
    final first = await connect(tester, socket);

    socket.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await reopen(tester, const Duration(seconds: 5));
    now = now.add(const Duration(seconds: 5));
    socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush(tester);

    expect(first.closed, isFalse);
    expect(links, hasLength(1));
    expect(stales(), 0);

    await socket.dispose();
  });

  testSocket(
    'forces a new socket on resume after a long absence, even when the grace timer never fired',
    (tester) async {
      final socket = socketOf();
      final first = await connect(tester, socket);

      socket.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush(tester);

      expect(first.closed, isTrue);
      expect(links, hasLength(2));

      await socket.dispose();
    },
  );

  testSocket(
    'has the holders read again after a long absence, even when it had never connected before',
    (tester) async {
      final socket = socketOf();

      await socket.start();
      await flush(tester);
      socket.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush(tester);
      links.last.receive({'type': 'auth_success', 'data': {}});
      await flush(tester);

      expect(stales(), 1);

      await socket.dispose();
    },
  );

  testSocket('reopens at once when the network comes back', (tester) async {
    final socket = socketOf();
    final first = await connect(tester, socket);

    first.drop();
    await flush(tester);
    online.add(true);
    await flush(tester);

    expect(links, hasLength(2));

    await socket.dispose();
  });
}
