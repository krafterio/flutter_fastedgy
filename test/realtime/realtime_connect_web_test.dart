/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter_fastedgy/src/realtime/realtime_connect_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test(
    'fails an opening the server turns down instead of waiting forever',
    () async {
      // What a browser meets while the API restarts: the handshake is refused.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.statusCode = HttpStatus.notFound;
        unawaited(request.response.close());
      });

      final opening = connectRealtime(
        Uri.parse('ws://${server.address.host}:${server.port}/api/ws'),
        const {},
      );

      await expectLater(
        opening.timeout(const Duration(seconds: 5)),
        throwsA(isA<WebSocketChannelException>()),
      );
    },
  );
}
