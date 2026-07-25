/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

Map<String, dynamic> _field(String name, String type) => {
  'name': name,
  'label': name,
  'type': type,
  'readonly': false,
  'required': false,
  'searchable': false,
  'extra': false,
  'filter_operators': <String>[],
  'target': null,
  'targets': null,
  'choices': null,
};

final _metadatas = {
  'user': {
    'name': 'user',
    'api_name': 'users',
    'label': 'User',
    'label_plural': 'Users',
    'searchable': false,
    'sortable': false,
    'sortable_field': null,
    'synchronizable': true,
    'fields': {'id': _field('id', 'integer'), 'name': _field('name', 'char')},
  },
};

/// Counts what the replica asks of it, and only answers once released — so a
/// test can hold several callers inside the same materialization.
class _CountingMetadataProvider implements MetadataProvider {
  int calls = 0;
  Map<String, dynamic>? payload;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async {
    calls++;
    await _gate.future;

    final data = payload;

    return data?.map(
      (key, value) =>
          MapEntry(key, MetadataModel.fromJson(value as Map<String, dynamic>)),
    );
  }

  @override
  String get scope => '';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Counts the migrations actually run — two concurrent [Replica.ensure] both
/// answering `needsSync` is expected, both migrating the table is not.
class _CountingReplicaStore extends ReplicaStore {
  _CountingReplicaStore({required super.databaseOpener});

  int migrations = 0;

  @override
  Future<ReplicaMigration> ensureModel(LocalModelSchema model) {
    migrations++;

    return super.ensureModel(model);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingReplicaStore store;
  late _CountingMetadataProvider metadata;
  late Replica replica;

  setUp(() async {
    store = _CountingReplicaStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
    );
    await store.open();
    metadata = _CountingMetadataProvider()..payload = _metadatas;
    replica = Replica(store, metadata);
  });

  tearDown(() => store.close());

  group('Replica single-flight', () {
    test('materializes the schema once for concurrent callers', () async {
      final schemas = Future.wait([
        replica.schema(),
        replica.schema(),
        replica.schema(),
      ]);
      metadata.release();

      for (final schema in await schemas) {
        expect(schema?.models['user'], isNotNull);
      }
      expect(metadata.calls, 1);
    });

    test('ensures a model once for concurrent callers', () async {
      metadata.release();

      final verdicts = await Future.wait([
        replica.ensure('user'),
        replica.ensure('user'),
      ]);

      expect(store.migrations, 1);
      // Both are told the table was just created: each of them is about to
      // sync, and neither may skip it believing the other covered it.
      expect(verdicts, [true, true]);
      expect(await replica.ensure('user'), isFalse);
      expect(store.migrations, 1);
    });

    test('materializes again after the metadata were unavailable', () async {
      metadata.payload = null;
      metadata.release();
      expect(await replica.schema(), isNull);

      metadata.payload = _metadatas;

      expect((await replica.schema())?.models['user'], isNotNull);
      expect(metadata.calls, 2);
    });
  });
}
