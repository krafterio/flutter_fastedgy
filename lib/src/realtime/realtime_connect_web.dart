/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime_socket.dart' show RealtimeConnection;

/// Opens the socket with the browser client.
///
/// [headers] are dropped: a browser hands none to the handshake. Nothing is
/// lost, the session is opened by the `authenticate` frame the socket sends
/// first and the User-Agent is the browser's own. The ping is the server's to
/// send as well, a browser answering it without being asked.
Future<RealtimeConnection> connectRealtime(
  Uri url,
  Map<String, dynamic> headers,
) async {
  final channel = WebSocketChannel.connect(url);

  try {
    await channel.ready.timeout(const Duration(seconds: 15));
  } catch (_) {
    await channel.sink.close();
    rethrow;
  }

  return RealtimeConnection(
    messages: channel.stream,
    send: channel.sink.add,
    close: () async {
      await channel.sink.close(ws_status.normalClosure);
    },
  );
}
