/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'realtime_socket.dart' show RealtimeConnection;

/// Opens the socket with the `dart:io` client, which carries [headers] in the
/// handshake.
Future<RealtimeConnection> connectRealtime(
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
