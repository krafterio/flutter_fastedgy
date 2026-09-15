/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../api/api_model_engine.dart';
import '../app_info/user_agent.dart';
import '../auth/auth_events.dart';
import '../auth/auth_provider.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import '../fetcher/http_error.dart';
import '../logging/logging.dart';
import 'origin.dart';
import 'realtime_events.dart';

/// `flow` for a list, `flow:42` for one record.
String channelOf(String model, [Object? id]) =>
    id == null ? model : '$model:$id';

/// Opens a connection to [url], sending [headers] with the handshake.
typedef RealtimeConnector = Future<RealtimeConnection> Function(
  Uri url,
  Map<String, dynamic> headers,
);

/// An open socket, reduced to what [RealtimeSocket] does with one.
class RealtimeConnection {
  const RealtimeConnection({
    required this.messages,
    required this.send,
    required this.close,
  });

  /// The frames received, done when the socket closes.
  final Stream<Object?> messages;
  final void Function(String frame) send;
  final Future<void> Function() close;
}

class _Expectation {
  _Expectation(this.model, this.id, this.at);

  final String model;
  final Object? id;
  final DateTime at;
}

/// The live half of the API: one socket per running application, on the scope
/// the application names, putting what the server announces on the bus.
///
/// Registered and started by `initializeFastEdgy(realtime: true)`.
class RealtimeSocket with WidgetsBindingObserver {
  RealtimeSocket({
    this._url,
    RealtimeConnector? connector,
    this._online,
    this.backgroundGrace = const Duration(seconds: 20),
    Bus? bus,
    AuthProvider? auth,
  }) : _connector = connector ?? _connect,
       _bus = bus ?? getService<Bus>(),
       _auth = auth ?? getService<AuthProvider>();

  static const _reconnectStart = Duration(seconds: 1);
  static const _reconnectMax = Duration(seconds: 30);
  static const _expectationLifetime = Duration(seconds: 30);
  static const _actions = {
    'created': ResourceChangeType.created,
    'updated': ResourceChangeType.updated,
    'deleted': ResourceChangeType.deleted,
  };

  /// How long the application may stay in the background before its socket
  /// closes: a suspended process cannot vouch for a connection past that.
  final Duration backgroundGrace;

  final Uri? _url;
  final RealtimeConnector _connector;
  final Stream<bool>? _online;
  final Bus _bus;
  final AuthProvider _auth;
  final _log = getLogger('RealtimeSocket');

  final _channels = <String, int>{};
  final _expected = <String, _Expectation>{};
  final _listeners = <StreamSubscription<Object?>>[];

  RealtimeConnection? _connection;
  StreamSubscription<Object?>? _frames;
  Timer? _retry;
  Timer? _grace;
  DateTime? _awaySince;
  Duration _delay = _reconnectStart;
  int _generation = 0;
  String? _scope;
  String? _announced;
  bool _started = false;
  bool _disposed = false;
  bool _wanted = false;
  bool _refused = false;
  bool _refreshed = false;
  bool _opening = false;
  bool _connected = false;
  bool _everConnected = false;
  bool _backgrounded = false;
  bool _owesStale = false;

  /// Whether the server accepted this socket, and it is still open.
  bool get isConnected => _connected;

  String? get scope => _scope;

  /// The socket address of an API base: the WebSocket scheme, `/ws` appended.
  static Uri urlOf(String apiBaseUrl) {
    final base = Uri.parse(apiBaseUrl);
    final path = base.path.endsWith('/') ? '${base.path}ws' : '${base.path}/ws';

    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: path,
    );
  }

  /// Follows sign-in, sign-out, the application lifecycle and connectivity,
  /// and opens when a session exists, without waiting for the connection.
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }

    _started = true;
    _listeners
      ..add(_bus.on<AuthLoggedEvent>().listen((_) => _signIn()))
      ..add(_bus.on<AuthLogoutEvent>().listen((_) => _signOut()))
      ..add((_online ?? _connectivity()).listen(_onOnline));
    WidgetsBinding.instance.addObserver(this);

    if (await _auth.isAuthenticated()) {
      _signIn();
    }
  }

  /// Reads [scope] from now on, a slug or null. The socket knows nothing of
  /// what a scope is: whoever knows it says so.
  void watch(String? scope) {
    if (scope == _scope) {
      return;
    }

    _scope = scope;

    if (_connected) {
      _announce();
    } else if (_refused) {
      // A scope the account is not a member of is refused too.
      _refused = false;
      _wanted = true;
      _refreshed = false;
      unawaited(_open());
    }
  }

  void subscribe(String model, [Object? id]) {
    final channel = channelOf(model, id);
    final held = _channels[channel] ?? 0;

    _channels[channel] = held + 1;

    if (held == 0 && _connected) {
      _send('subscribe', {
        'channels': [channel],
      });
    }
  }

  void unsubscribe(String model, [Object? id]) {
    final channel = channelOf(model, id);
    final held = _channels[channel];

    if (held == null) {
      return;
    }

    if (held > 1) {
      _channels[channel] = held - 1;

      return;
    }

    _channels.remove(channel);

    if (_connected) {
      _send('unsubscribe', {
        'channels': [channel],
      });
    }
  }

  /// Expects the echo of a write about to leave under [origin], the request's
  /// own: the frame answering it is dropped once, the api layer announcing that
  /// change when the request answers.
  void expect(String origin, String model, [Object? id]) {
    final now = clock.now();

    _expected
      ..removeWhere((_, one) => now.difference(one.at) > _expectationLifetime)
      ..[origin] = _Expectation(model, id, now);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _wanted = false;

    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }

    // Not awaited: a cancellation takes effect at once, and its future may
    // belong to a zone nothing drives any more.
    for (final listener in _listeners) {
      unawaited(listener.cancel());
    }

    _listeners.clear();
    _retry?.cancel();
    _grace?.cancel();
    await _close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _leave();
      case AppLifecycleState.resumed:
        unawaited(_resume());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  void _signIn() {
    _wanted = true;
    _refused = false;
    _refreshed = false;
    unawaited(_open());
  }

  // The channels stay: a service outlives a sign-out, and the next session
  // says them again.
  void _signOut() {
    _wanted = false;
    _refused = false;
    _retry?.cancel();
    _retry = null;
    unawaited(_close());
  }

  Future<void> _open() async {
    if (_disposed ||
        !_wanted ||
        _backgrounded ||
        _opening ||
        _connection != null) {
      return;
    }

    _opening = true;
    _retry?.cancel();
    _retry = null;

    final generation = _generation;
    var superseded = false;

    try {
      final token = await _auth.getValidatedAccessToken();

      if (generation != _generation) {
        superseded = true;

        return;
      }

      if (token == null || token.isEmpty) {
        return;
      }

      final connection = await _connector(_socketUrl, {
        if (hasService<UserAgent>())
          'User-Agent': getService<UserAgent>().value,
      });

      if (generation != _generation || !_wanted || _disposed) {
        superseded = true;
        await connection.close();

        return;
      }

      _connection = connection;
      _announced = _scope;
      _frames = connection.messages.listen(
        _receive,
        onError: (Object _) => _lost(connection),
        onDone: () => _lost(connection),
      );
      connection.send(
        jsonEncode({
          'type': 'authenticate',
          'data': {'token': token, 'scope': _scope},
        }),
      );
    } catch (error) {
      _log.fine('Realtime socket could not open', error);

      if (generation == _generation) {
        _scheduleRetry();
      } else {
        superseded = true;
      }
    } finally {
      _opening = false;

      // A close landed while this opening was under way: an opening asked for
      // since found this one busy, and is made now.
      if (superseded) {
        unawaited(_open());
      }
    }
  }

  Uri get _socketUrl =>
      _url ??
      urlOf(dotenv.isInitialized ? dotenv.env['API_BASE_URL'] ?? '' : '');

  void _receive(Object? frame) {
    if (frame is! String) {
      return;
    }

    final Object? message;

    try {
      message = jsonDecode(frame);
    } on FormatException {
      return;
    }

    if (message is! Map<String, dynamic>) {
      return;
    }

    final type = message['type'];

    if (type == 'auth_success') {
      _handshake();

      return;
    }

    if (type == 'auth_error') {
      unawaited(_refusal());

      return;
    }

    if (type is! String) {
      return;
    }

    final data = message['data'];
    final origin = message['origin'] is String
        ? message['origin'] as String
        : null;
    final truncated = message['truncated'] == true;
    final dot = type.indexOf('.');
    final action = dot > 0 ? _actions[type.substring(dot + 1)] : null;

    if (action == null) {
      _bus.fire(RealtimeEvent(type, data, truncated: truncated));

      return;
    }

    final model = type.substring(0, dot);
    final carried = data is Map<String, dynamic> ? data : null;
    final id = carried?['id'];

    if (_answers(origin, model, id)) {
      return;
    }

    final changed = message['changed'];

    _bus.fire(
      ResourceChangedEvent(
        null,
        model: model,
        type: action,
        id: id,
        fields: changed is List ? {for (final one in changed) '$one'} : null,
        data: carried,
        origin: _ownOrigin(origin),
        truncated: truncated,
        announced: true,
      ),
    );
  }

  void _handshake() {
    _connected = true;
    _refreshed = false;
    _delay = _reconnectStart;

    if (_scope != _announced) {
      _announce();
    } else if (_channels.isNotEmpty) {
      _send('subscribe', {'channels': _channels.keys.toList()});
    }

    // After the channels: a holder that reads again once its subscription left
    // misses less than one reading before.
    if (_everConnected || _owesStale) {
      _owesStale = false;
      _bus.fire(const ResourcesStaleEvent());
    }

    _everConnected = true;
  }

  // The server drops what a socket subscribed to when it moves to another scope.
  void _announce() {
    if (_scope == _announced) {
      return;
    }

    _announced = _scope;
    _send('watch', {'scope': _scope});

    if (_channels.isNotEmpty) {
      _send('subscribe', {'channels': _channels.keys.toList()});
    }
  }

  Future<void> _refusal() async {
    await _close();

    if (!_wanted) {
      return;
    }

    if (!_refreshed) {
      _refreshed = true;

      try {
        if (await _auth.refreshToken()) {
          unawaited(_open());

          return;
        }
      } catch (error) {
        if (isServerUnavailable(error)) {
          _scheduleRetry();

          return;
        }
      }
    }

    // A refusal does not fix itself: closed until a sign-in, a return to the
    // foreground, or another scope.
    if (_wanted) {
      _wanted = false;
      _refused = true;
    }
  }

  void _lost(RealtimeConnection connection) {
    if (!identical(connection, _connection)) {
      return;
    }

    _connection = null;
    _frames = null;
    _connected = false;
    _announced = null;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || !_wanted || _backgrounded || _retry != null) {
      return;
    }

    _retry = Timer(_delay, () {
      _retry = null;
      unawaited(_open());
    });

    final doubled = _delay * 2;

    _delay = doubled > _reconnectMax ? _reconnectMax : doubled;
  }

  Future<void> _close() async {
    _generation++;

    final connection = _connection;
    final frames = _frames;

    _connection = null;
    _frames = null;
    _connected = false;
    _announced = null;

    if (frames != null) {
      unawaited(frames.cancel());
    }

    if (connection != null) {
      try {
        await connection.close();
      } catch (error) {
        _log.fine('Realtime socket did not close cleanly', error);
      }
    }
  }

  void _send(String type, Object? data) =>
      _connection?.send(jsonEncode({'type': type, 'data': data}));

  bool _answers(String? origin, String model, Object? id) {
    final expected = origin == null ? null : _expected[origin];

    if (expected == null ||
        expected.model != model ||
        clock.now().difference(expected.at) > _expectationLifetime) {
      return false;
    }

    if (expected.id != null && (id == null || '${expected.id}' != '$id')) {
      return false;
    }

    _expected.remove(origin);

    return true;
  }

  // Any request of this instance is this instance, for a view comparing
  // origins with [originId].
  static String? _ownOrigin(String? origin) =>
      origin != null && (origin == originId || origin.startsWith('$originId.'))
      ? originId
      : origin;

  void _leave() {
    if (_awaySince != null) {
      return;
    }

    _awaySince = clock.now();
    _grace?.cancel();
    _grace = Timer(backgroundGrace, () {
      _grace = null;
      _backgrounded = true;
      _retry?.cancel();
      _retry = null;
      unawaited(_close());
    });
  }

  Future<void> _resume() async {
    final awaySince = _awaySince;

    _awaySince = null;
    _grace?.cancel();
    _grace = null;
    _backgrounded = false;

    if (awaySince == null || _disposed) {
      return;
    }

    if (!_wanted) {
      if (!await _auth.isAuthenticated()) {
        return;
      }

      _wanted = true;
      _refused = false;
      _refreshed = false;
    }

    // Timers stand still while the process is suspended: the clock says how
    // long it was away.
    if (clock.now().difference(awaySince) >= backgroundGrace) {
      _owesStale = true;
      await _close();
    }

    _delay = _reconnectStart;
    await _open();
  }

  void _onOnline(bool online) {
    if (!online || _connection != null || _opening) {
      return;
    }

    _delay = _reconnectStart;
    unawaited(_open());
  }

  static Stream<bool> _connectivity() =>
      Connectivity().onConnectivityChanged.map(
        (results) => results.any((result) => result != ConnectivityResult.none),
      );
}

Future<RealtimeConnection> _connect(
  Uri url,
  Map<String, dynamic> headers,
) async {
  final socket = await WebSocket.connect(
    '$url',
    headers: headers,
  ).timeout(const Duration(seconds: 15));

  // A ping rather than a heartbeat frame: it keeps an idle flow warm all the
  // same, and a socket that died without a close answers no pong.
  socket.pingInterval = const Duration(seconds: 30);

  return RealtimeConnection(
    messages: socket,
    send: socket.add,
    close: () async {
      await socket.close(WebSocketStatus.normalClosure);
    },
  );
}
