/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements ResourceRelayTransport {
  final sent = <Map<String, dynamic>>[];
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<void> start() async {}

  @override
  void broadcast(Map<String, dynamic> event) => sent.add(event);

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  void receive(Map<String, dynamic> event) => _incoming.add(event);

  @override
  Future<void> dispose() => _incoming.close();
}

void main() {
  late Bus bus;
  late _Transport transport;
  late ResourceEventRelay relay;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    bus = Bus();
    transport = _Transport();
    relay = ResourceEventRelay(transport, bus: bus);
    await relay.start();
  });

  tearDown(() => relay.dispose());

  test('forwards a write of this instance', () async {
    bus.fire(const ResourceChangedEvent('/things', model: 'thing', id: 7));
    await settle();

    expect(transport.sent.single['model'], 'thing');
  });

  test(
    'never forwards what the server announced, nor what it relayed',
    () async {
      bus.fire(
        const ResourceChangedEvent(
          null,
          model: 'thing',
          id: 7,
          announced: true,
        ),
      );
      bus.fire(const ResourceChangedEvent('/things', relayed: true));
      await settle();

      expect(transport.sent, isEmpty);
    },
  );

  test('fires what another instance relays, flagged relayed', () async {
    final heard = <ResourceChangedEvent>[];

    bus.on<ResourceChangedEvent>().listen(heard.add);
    transport.receive({'model': 'thing', 'id': 7, 'origin': 'sibling'});
    await settle();

    expect(heard.single.relayed, isTrue);
    expect(heard.single.model, 'thing');
    expect(transport.sent, isEmpty);
  });
}
