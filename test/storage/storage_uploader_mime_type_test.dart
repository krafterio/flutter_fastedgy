/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<FormData> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    bodies.add(options.data as FormData);

    return ResponseBody.fromString(
      jsonEncode(
        options.path.endsWith('/attachments')
            ? {'attachments': <Object>[]}
            : {'path': 'documents/1/file'},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _types = {
  'rapport.doc': 'application/msword',
  'rapport.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'budget.xls': 'application/vnd.ms-excel',
  'budget.xlsx':
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'slides.ppt': 'application/vnd.ms-powerpoint',
  'slides.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'lettre.rtf': 'application/rtf',
  'lettre.odt': 'application/vnd.oasis.opendocument.text',
  'tableau.ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'diapos.odp': 'application/vnd.oasis.opendocument.presentation',
  'liste.csv': 'text/csv',
};

void main() {
  late _RecordingAdapter adapter;
  late StorageUploader uploader;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }
  });

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter;
    uploader = StorageUploader(
      Fetcher.create(
        dio: dio,
        bus: getService<Bus>(),
        enableAuth: false,
        enableTimezone: false,
        enableRefreshToken: false,
        enableConnectionRetry: false,
        enableLogging: false,
        enableErrorTransform: false,
      ),
      prefix: '',
    );
  });

  test('a document sent to a field goes with the type of its format', () async {
    for (final name in _types.keys) {
      await uploader.uploadModelFieldFromBytes(
        model: 'documents',
        modelId: 1,
        field: 'file',
        bytes: Uint8List.fromList([1]),
        fileName: name,
      );
    }

    expect({
      for (final body in adapter.bodies)
        body.files.single.value.filename:
            body.files.single.value.contentType?.mimeType,
    }, _types);
  });

  test('an attachment goes with the type of its format', () async {
    await uploader.uploadAttachmentsFromBytes(
      {
        for (final name in _types.keys) name: Uint8List.fromList([1]),
      },
      filenames: {for (final name in _types.keys) name: name},
    );

    expect({
      for (final file in adapter.bodies.single.files)
        file.value.filename: file.value.contentType?.mimeType,
    }, _types);
  });
}
