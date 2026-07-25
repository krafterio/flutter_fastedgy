/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  bool offline = false;
  final List<String> calls = [];
  final List<FormData> bodies = [];
  Map<String, dynamic> Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');

    if (options.data is FormData) {
      bodies.add(options.data as FormData);
    }

    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }

    final payload = handler?.call(options) ?? const <String, dynamic>{};

    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StubMetadataProvider implements MetadataProvider {
  static const _attachment = MetadataModel(
    name: 'attachment',
    apiName: 'attachments',
    label: 'Attachment',
    labelPlural: 'Attachments',
    searchable: false,
    sortable: false,
    synchronizable: true,
    synchronizableMode: 'partial',
    fields: {},
  );

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() async => const {
    'attachment': _attachment,
  };

  @override
  Future<MetadataModel?> getMetadata(String name) async =>
      name == 'attachment' ? _attachment : null;

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

Future<Map<String, String>> _formFields(FormData data) async {
  return {for (final field in data.fields) field.key: field.value};
}

/// The store keeps its blobs in a subdirectory of the one it is given.
List<FileSystemEntity> _blobs(Directory root) {
  final dir = Directory('${root.path}/fastedgy_pending_uploads');

  return dir.existsSync() ? dir.listSync() : const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _ScriptedAdapter adapter;
  late DriftLocalStore store;
  late PendingUploadStore uploads;
  late LocalSequence sequence;
  late Outbox outbox;
  late Fetcher fetcher;
  late StorageUploader uploader;
  late SyncEngine engine;
  late DriftLocalImageStore previews;
  late List<OutboxOperationDiscardedEvent> discarded;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    tempDir = await Directory.systemTemp.createTemp('pending_uploads_test');
    final db = OfflineDatabase(NativeDatabase.memory());

    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.httpClientAdapter = adapter;
    fetcher = Fetcher.create(
      dio: dio,
      bus: getService<Bus>(),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
      enableConnectionRetry: false,
      enableLogging: false,
      enableErrorTransform: false,
    );

    store = DriftLocalStore(databaseOpener: () => db);
    await store.open();
    uploads = PendingUploadStore(
      databaseOpener: () => db,
      directoryOpener: () async => tempDir,
    );
    await uploads.open();
    sequence = LocalSequence(databaseOpener: () => db);
    await sequence.open();
    previews = DriftLocalImageStore(databaseOpener: () => db);
    await previews.open();

    outbox = Outbox(store);
    uploader = StorageUploader(
      fetcher,
      prefix: '',
      outbox: outbox,
      uploads: uploads,
      sequence: sequence,
      images: previews,
    );
    engine = SyncEngine(
      outbox,
      fetcher,
      getService<Bus>(),
      localStore: store,
      uploads: uploads,
      images: previews,
    );

    discarded = [];
    getService<Bus>().on<OutboxOperationDiscardedEvent>().listen(discarded.add);
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
  });

  group('PendingUploadStore', () {
    test('round-trips bytes and metadata', () async {
      final buffered = await uploads.put(
        Uint8List.fromList([1, 2, 3]),
        fileName: 'brief.pdf',
        mimeType: 'application/pdf',
      );

      expect(buffered.ref, startsWith('local://'));
      expect(buffered.sizeBytes, 3);
      expect(await uploads.bytes(buffered.id), [1, 2, 3]);

      final entry = await uploads.get(buffered.id);

      expect(entry!.fileName, 'brief.pdf');
      expect(entry.mimeType, 'application/pdf');
    });

    test('resolves a local reference back to its id', () async {
      final buffered = await uploads.put(
        Uint8List.fromList([1]),
        fileName: 'a.txt',
      );

      expect(pendingUploadIdOf(buffered.ref), buffered.id);
      expect(pendingUploadIdOf('attachments/2026/07/real.pdf'), isNull);
      expect(pendingUploadIdOf(null), isNull);
    });

    test('remove drops the row and the file', () async {
      final buffered = await uploads.put(
        Uint8List.fromList([1]),
        fileName: 'a.txt',
      );

      await uploads.remove(buffered.id);

      expect(await uploads.get(buffered.id), isNull);
      expect(await uploads.bytes(buffered.id), isNull);
      expect(_blobs(tempDir), isEmpty);
    });

    test('clearAll drops everything', () async {
      await uploads.put(Uint8List.fromList([1]), fileName: 'a.txt');
      await uploads.put(Uint8List.fromList([2]), fileName: 'b.txt');

      await uploads.clearAll();

      expect(await uploads.all(), isEmpty);
      expect(_blobs(tempDir), isEmpty);
    });

    test('a file removed out of band reads as absent', () async {
      final buffered = await uploads.put(
        Uint8List.fromList([1]),
        fileName: 'a.txt',
      );
      await File(
        '${tempDir.path}/fastedgy_pending_uploads/${buffered.id}',
      ).delete();

      expect(await uploads.bytes(buffered.id), isNull);
    });
  });

  group('buffered attachment upload', () {
    test('an offline upload is buffered instead of failing', () async {
      adapter.offline = true;

      final attachments = await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
      );

      expect(attachments, hasLength(1));
      expect(attachments.single.id, isNegative);
      expect(attachments.single.getBool('_offline_pending'), isTrue);
      expect(
        attachments.single.getString('_local_path'),
        startsWith('local://'),
      );
      expect(attachments.single.getString('name'), 'brief');
      expect(attachments.single.getString('extension'), 'pdf');

      // One operation per file, so each is replayed and counted on its own.
      final operations = await outbox.all();
      expect(operations, hasLength(1));
      expect(operations.single.isUpload, isTrue);
      expect(operations.single.model, 'attachment');
      expect(await uploads.all(), hasLength(1));
    });

    test('the base path uses the api_name from the metadata', () async {
      adapter.offline = true;

      // No metadata wired here: the model name stands in rather than a guessed
      // plural.
      await uploader.uploadAttachmentsFromBytes(
        {
          'a.pdf': Uint8List.fromList([1]),
        },
        filenames: {'a.pdf': 'a.pdf'},
      );

      expect((await outbox.all()).single.basePath, '/attachment');

      final described = StorageUploader(
        fetcher,
        prefix: '',
        outbox: outbox,
        uploads: uploads,
        sequence: sequence,
        metadatas: _StubMetadataProvider(),
      );
      await described.uploadAttachmentsFromBytes(
        {
          'b.pdf': Uint8List.fromList([2]),
        },
        filenames: {'b.pdf': 'b.pdf'},
      );

      expect((await outbox.all()).last.basePath, '/attachments');
    });

    test('each file gets its own operation', () async {
      adapter.offline = true;

      await uploader.uploadAttachmentsFromBytes(
        {
          'a.pdf': Uint8List.fromList([1]),
          'b.pdf': Uint8List.fromList([2]),
          'c.pdf': Uint8List.fromList([3]),
        },
        filenames: {'a.pdf': 'a.pdf', 'b.pdf': 'b.pdf', 'c.pdf': 'c.pdf'},
      );

      expect(await outbox.all(), hasLength(3));
      expect(await uploads.all(), hasLength(3));

      // Distinct temporary ids inside the attachment scope.
      final ids = (await outbox.all()).map((o) => o.recordId).toSet();
      expect(ids, hasLength(3));
    });

    test('carries the owner so the replay associates in one request', () async {
      adapter.offline = true;

      await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
        meta: {
          'record': {'model': 'flow', 'id': -1},
        },
      );

      final operation = (await outbox.all()).single;

      expect(operation.upload!.meta, {
        'record': {'model': 'flow', 'id': -1},
      });
    });

    test('replays the buffered upload and heals the record', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
        meta: {
          'record': {'model': 'flow', 'id': 42},
        },
      );
      final tempId = buffered.single.id;

      adapter.offline = false;
      adapter.handler = (_) => {
        'attachments': [
          {
            'id': 100,
            'name': 'brief',
            'extension': 'pdf',
            'storage_path': 'attachments/2026/07/real.pdf',
          },
        ],
      };
      await engine.flush();

      // The multipart carried the association.
      final fields = await _formFields(adapter.bodies.last);
      expect(jsonDecode(fields['meta']!), {
        'record': {'model': 'flow', 'id': 42},
      });

      expect(await outbox.all(), isEmpty);

      // The server record replaced the optimistic one.
      expect(await store.get('attachment', 100), isNotNull);
      expect(await store.get('attachment', tempId!), isNull);

      // The server holds the file now: the local copy is reclaimed.
      expect(await uploads.all(), isEmpty);
      expect(_blobs(tempDir), isEmpty);
    });

    test('resolves an owner created offline on replay', () async {
      adapter.offline = true;

      // The flow does not exist server-side yet: its temporary id must be
      // swapped before the attachment is sent.
      await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
        meta: {
          'record': {'model': 'flow', 'id': -1},
        },
      );

      // Mapping the flow's create left behind.
      await store.put('_outbox_idmap', 'flow:-1', {
        'scope': 'flow',
        'temp': -1,
        'server': 42,
      });

      adapter.offline = false;
      adapter.handler = (_) => {
        'attachments': [
          {'id': 100, 'name': 'brief'},
        ],
      };
      await engine.flush();

      final fields = await _formFields(adapter.bodies.last);
      expect(jsonDecode(fields['meta']!), {
        'record': {'model': 'flow', 'id': 42},
      });
    });

    test('a connectivity failure keeps the file and the operation', () async {
      adapter.offline = true;

      await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
      );

      // Still offline when the flush runs: nothing may be lost.
      await engine.flush();

      expect(await outbox.all(), hasLength(1));
      expect(await uploads.all(), hasLength(1));
      expect(_blobs(tempDir), hasLength(1));
      expect(discarded, isEmpty);
    });

    test('a rejected upload drops the file', () async {
      adapter.offline = true;

      await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
      );

      adapter.offline = false;
      adapter.handler = (options) => throw badRequest(options);
      await engine.flush();

      expect(await outbox.all(), isEmpty);
      expect(discarded, hasLength(1));
      expect(discarded.single.reason, 'rejected');

      // Definitively refused: keeping the bytes would leak storage forever.
      expect(await uploads.all(), isEmpty);
      expect(_blobs(tempDir), isEmpty);
    });

    test('a missing buffered file leaves nothing behind', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'shot.jpg': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'shot.jpg': 'shot.jpg'},
      );
      final ref = buffered.single.getString('_local_path')!;
      final uploadId = pendingUploadIdOf(ref)!;

      // Only the bytes vanish (removed out of band): the index row and the
      // preview survive them, and would outlive the operation.
      await File('${tempDir.path}/fastedgy_pending_uploads/$uploadId').delete();

      adapter.offline = false;
      await engine.flush();

      expect(await outbox.all(), isEmpty);
      expect(await uploads.get(uploadId), isNull);
      expect(await previews.getBestVariant(ref), isNull);
    });

    test('a missing buffered file drops its operation', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
      );
      final uploadId = (await outbox.all()).single.upload!.uploadId;
      await uploads.remove(uploadId);

      adapter.offline = false;
      await engine.flush();

      // Nothing left to send: retrying forever would block the queue.
      expect(await outbox.all(), isEmpty);
      expect(discarded, hasLength(1));
      expect(buffered.single.id, isNegative);
    });

    test('a buffered image stays displayable while it waits', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'shot.jpg': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'shot.jpg': 'shot.jpg'},
      );
      final ref = buffered.single.getString('_local_path')!;

      // Stored with no dimensions, so the image pipeline's getBestVariant
      // fallback serves it as the original — no special case in the widgets.
      expect(await previews.getBestVariant(ref), [1, 2, 3]);
    });

    test('a buffered document gets no preview', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
      );
      final ref = buffered.single.getString('_local_path')!;

      expect(await previews.getBestVariant(ref), isNull);
    });

    test('the preview is reclaimed with the file on replay', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'shot.jpg': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'shot.jpg': 'shot.jpg'},
      );
      final ref = buffered.single.getString('_local_path')!;

      adapter.offline = false;
      adapter.handler = (_) => {
        'attachments': [
          {'id': 100, 'name': 'shot'},
        ],
      };
      await engine.flush();

      // The server rendition is the reference from now on.
      expect(await previews.getBestVariant(ref), isNull);
      expect(await previews.paths(), isEmpty);
    });

    test('a rejected upload reclaims its preview too', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'shot.jpg': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'shot.jpg': 'shot.jpg'},
      );
      final ref = buffered.single.getString('_local_path')!;

      adapter.offline = false;
      adapter.handler = (options) => throw badRequest(options);
      await engine.flush();

      expect(await previews.getBestVariant(ref), isNull);
    });

    test('an offline failure keeps the preview', () async {
      adapter.offline = true;

      final buffered = await uploader.uploadAttachmentsFromBytes(
        {
          'shot.jpg': Uint8List.fromList([1, 2, 3]),
        },
        filenames: {'shot.jpg': 'shot.jpg'},
      );
      final ref = buffered.single.getString('_local_path')!;

      await engine.flush();

      expect(await previews.getBestVariant(ref), [1, 2, 3]);
    });

    test('an online upload never touches the outbox', () async {
      adapter.handler = (_) => {
        'attachments': [
          {'id': 100, 'name': 'brief'},
        ],
      };

      final attachments = await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
      );

      expect(attachments.single.id, 100);
      expect(await outbox.all(), isEmpty);
      expect(await uploads.all(), isEmpty);
    });

    test('sends meta on the online path too', () async {
      adapter.handler = (_) => {
        'attachments': [
          {'id': 100},
        ],
      };

      await uploader.uploadAttachmentsFromBytes(
        {
          'brief.pdf': Uint8List.fromList([1]),
        },
        filenames: {'brief.pdf': 'brief.pdf'},
        meta: {
          'record': {'model': 'flow', 'id': 42},
        },
      );

      final fields = await _formFields(adapter.bodies.last);
      expect(jsonDecode(fields['meta']!), {
        'record': {'model': 'flow', 'id': 42},
      });
    });

    test('without offline services an upload still fails', () async {
      final online = StorageUploader(fetcher, prefix: '');
      adapter.offline = true;

      expect(online.canBuffer, isFalse);
      await expectLater(
        online.uploadAttachmentsFromBytes(
          {
            'a.pdf': Uint8List.fromList([1]),
          },
          filenames: {'a.pdf': 'a.pdf'},
        ),
        throwsA(anything),
      );
    });
  });

  group('buffered model field upload', () {
    test('buffers and replays a model field upload', () async {
      adapter.offline = true;

      final file = File('${tempDir.path}/avatar.png')
        ..writeAsBytesSync([1, 2, 3]);
      final result = await uploader.uploadModelField(
        model: 'user',
        modelId: 7,
        field: 'avatar',
        file: file,
      );

      // The local reference stands in for the storage path meanwhile.
      expect(result.path, startsWith('local://'));

      final operation = (await outbox.all()).single;
      expect(operation.isUpload, isTrue);
      expect(operation.upload!.kind, PendingUploadRequest.kindModelField);
      expect(operation.upload!.field, 'avatar');
      expect(operation.recordId, 7);

      adapter.offline = false;
      adapter.handler = (_) => {'path': 'user/real.png'};
      await engine.flush();

      expect(adapter.calls.last, 'POST /storage/upload/user/7/avatar');
      expect(await outbox.all(), isEmpty);
      expect(await uploads.all(), isEmpty);
    });

    test('healing one field keeps the rest of the record', () async {
      // The stores replace a record wholesale, so writing back the two keys the
      // upload resolves would erase everything else about the record.
      await store.put('user', 7, {
        'id': 7,
        'name': 'Ada',
        'email': 'ada@example.com',
      });

      adapter.offline = true;
      final file = File('${tempDir.path}/avatar.png')
        ..writeAsBytesSync([1, 2, 3]);
      await uploader.uploadModelField(
        model: 'user',
        modelId: 7,
        field: 'avatar',
        file: file,
      );

      adapter.offline = false;
      adapter.handler = (_) => {'path': 'user/real.png'};
      await engine.flush();

      expect(await store.get('user', 7), {
        'id': 7,
        'name': 'Ada',
        'email': 'ada@example.com',
        'avatar': 'user/real.png',
      });
    });

    test('a field upload for an unmirrored record writes nothing', () async {
      adapter.offline = true;
      final file = File('${tempDir.path}/avatar2.png')
        ..writeAsBytesSync([1, 2, 3]);
      await uploader.uploadModelField(
        model: 'user',
        modelId: 99,
        field: 'avatar',
        file: file,
      );

      adapter.offline = false;
      adapter.handler = (_) => {'path': 'user/real.png'};
      await engine.flush();

      // Nothing to merge onto: mirroring a record made of a single field would
      // be worse than mirroring nothing.
      expect(await store.get('user', 99), isNull);
      expect(await outbox.all(), isEmpty);
      expect(await uploads.all(), isEmpty);
    });
  });
}

DioException badRequest(RequestOptions options) => DioException(
  requestOptions: options,
  response: Response(requestOptions: options, statusCode: 400),
  type: DioExceptionType.badResponse,
);
