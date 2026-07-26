/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _MockMetadataProvider implements MetadataProvider {
  final Map<String, MetadataModel> _map;

  _MockMetadataProvider(this._map);

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => _map;

  @override
  Future<MetadataModel?> getMetadata(String name) async => _map[name];

  @override
  Future<void> fetchMetadatas() async {}

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

MetadataModel _model(String name, {required String mode}) => MetadataModel(
  name: name,
  apiName: '${name}s',
  label: name,
  labelPlural: '${name}s',
  searchable: false,
  sortable: false,
  synchronizable: mode != 'none',
  synchronizableMode: mode,
  fields: const {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SyncStatus status;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    container.registerSingleton<MetadataProvider>(
      _MockMetadataProvider({
        'thing': _model('thing', mode: 'partial'),
        'mirrored': _model('mirrored', mode: 'full'),
        'strict': _model('strict', mode: 'none'),
      }),
    );
  });

  setUp(() {
    status = SyncStatus(getService<Bus>());
    container.registerSingleton<SyncStatus>(status);
  });

  tearDown(() => container.unregister<SyncStatus>());

  group('ModelCapability.of', () {
    test('reads the regime the server declared', () async {
      expect((await ModelCapability.of('thing')).synchronizableMode, 'partial');
      expect((await ModelCapability.of('thing')).isPartiallyMirrored, isTrue);
      expect(
        (await ModelCapability.of('mirrored')).isPartiallyMirrored,
        isFalse,
      );
      expect((await ModelCapability.of('mirrored')).isReplicated, isTrue);
      expect((await ModelCapability.of('strict')).isReplicated, isFalse);
    });

    test(
      'a replicated model buffers its writes once the outbox is wired',
      () async {
        expect((await ModelCapability.of('thing')).bufferizesWrites, isTrue);
        expect((await ModelCapability.of('strict')).bufferizesWrites, isFalse);
      },
    );

    test('nothing buffers without the offline write path', () async {
      container.unregister<SyncStatus>();

      // An online-only build: a replicated model is still declared as such, but
      // there is nowhere to keep a write.
      final capability = await ModelCapability.of('thing');

      expect(capability.isPartiallyMirrored, isTrue);
      expect(capability.bufferizesWrites, isFalse);

      container.registerSingleton<SyncStatus>(status);
    });

    test('an unknown model claims nothing', () async {
      expect(await ModelCapability.of('nope'), ModelCapability.unknown);
      expect(ModelCapability.unknown.isReplicated, isFalse);
      expect(ModelCapability.unknown.canWrite(serverReachable: false), isFalse);
      expect(ModelCapability.unknown.canWrite(serverReachable: true), isTrue);
    });
  });

  group('ModelCapability.canWrite', () {
    test('a reachable server always allows a write', () {
      const strict = ModelCapability(synchronizableMode: 'none');

      expect(strict.canWrite(serverReachable: true), isTrue);
      expect(strict.canWrite(serverReachable: false), isFalse);
    });

    test('a buffered model allows a write with no server at all', () {
      const buffered = ModelCapability(
        synchronizableMode: 'partial',
        bufferizesWrites: true,
      );

      expect(buffered.canWrite(serverReachable: false), isTrue);
    });
  });

  group('ModelAvailability', () {
    test(
      'answers for a model with no collection or record behind it',
      () async {
        final access = ModelAvailability('thing');
        await pumpEventQueue();

        expect(access.resolved, isTrue);
        expect(access.canWrite, isTrue);
        expect(access.requiresConnection, isFalse);

        access.dispose();
      },
    );

    test('follows connectivity and notifies', () async {
      final strict = ModelAvailability('strict');
      final buffered = ModelAvailability('thing');
      await pumpEventQueue();

      var notified = 0;
      strict.addListener(() => notified++);

      status.setOnline(false);
      await pumpEventQueue();

      expect(notified, greaterThan(0));
      // The button of an online-only model grays out; the one that buffers does
      // not, and neither had to read anything to know.
      expect(strict.canWrite, isFalse);
      expect(strict.requiresConnection, isTrue);
      expect(buffered.canWrite, isTrue);
      expect(buffered.requiresConnection, isFalse);

      status.setOnline(true);
      await pumpEventQueue();

      expect(strict.canWrite, isTrue);
      expect(strict.requiresConnection, isFalse);

      strict.dispose();
      buffered.dispose();
    });

    test('holds an action back while the capability is unknown', () async {
      status.setOnline(false);

      final access = ModelAvailability('thing');

      // Not resolved yet: offering an action that would be lost is worse than
      // offering it one frame late.
      expect(access.resolved, isFalse);
      expect(access.canWrite, isFalse);

      await pumpEventQueue();

      expect(access.resolved, isTrue);
      expect(access.canWrite, isTrue);

      access.dispose();
    });

    test('stops notifying once disposed', () async {
      final access = ModelAvailability('strict');
      await pumpEventQueue();

      var notified = 0;
      access.addListener(() => notified++);
      access.dispose();

      status.setOnline(false);
      await pumpEventQueue();

      expect(notified, 0);
    });
  });

  group('canWriteModel', () {
    test('answers once, without a listener to dispose', () async {
      expect(await canWriteModel('strict'), isTrue);
      expect(await canWriteModel('thing'), isTrue);

      status.setOnline(false);

      expect(await canWriteModel('strict'), isFalse);
      expect(await canWriteModel('thing'), isTrue);
    });
  });
}
