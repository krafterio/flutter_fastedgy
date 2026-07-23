/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FilesystemLocalImageStore store;

  Iterable<File> files() => Directory(
    '${tmp.path}/fastedgy_offline_images',
  ).listSync().whereType<File>();
  Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

  setUp(() async {
    OfflineDatabase.allowMultipleInstances();
    tmp = await Directory.systemTemp.createTemp('fastedgy_img_test');
    store = FilesystemLocalImageStore(
      databaseOpener: () => OfflineDatabase(NativeDatabase.memory()),
      directoryOpener: () async => tmp,
    );
    await store.open();
  });

  tearDown(() async {
    await store.close();
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test(
    'stores the bytes on disk (not in the database) and reads them back',
    () async {
      await store.putVariant(
        'img/a',
        'w256',
        bytes('AAA'),
        width: 256,
        height: 256,
      );

      expect(await store.getVariant('img/a', 'w256'), bytes('AAA'));
      expect(await store.hasVariant('img/a', 'w256'), isTrue);
      expect(files(), hasLength(1));
    },
  );

  test(
    'getBestVariant prefers the original, then the largest rendition',
    () async {
      await store.putVariant(
        'img/a',
        'w64',
        bytes('small'),
        width: 64,
        height: 64,
      );
      await store.putVariant(
        'img/a',
        'w256',
        bytes('big'),
        width: 256,
        height: 256,
      );
      await store.putVariant('img/a', 'orig', bytes('original'));

      expect(await store.getBestVariant('img/a'), bytes('original'));
    },
  );

  test('removePath deletes the files and rows of one path only', () async {
    await store.putVariant('img/a', 'w1', bytes('x'));
    await store.putVariant('img/a', 'w2', bytes('y'));
    await store.putVariant('img/b', 'w1', bytes('z'));

    await store.removePath('img/a');

    expect(await store.getVariant('img/a', 'w1'), isNull);
    expect(await store.getVariant('img/b', 'w1'), bytes('z'));
    expect(await store.paths(), ['img/b']);
    expect(files(), hasLength(1));
  });

  test('a file deleted out of band resolves to null', () async {
    await store.putVariant('img/a', 'w1', bytes('x'));
    files().single.deleteSync();

    expect(await store.getVariant('img/a', 'w1'), isNull);
  });

  test('clear removes every file and row', () async {
    await store.putVariant('img/a', 'w1', bytes('x'));
    await store.putVariant('img/b', 'w1', bytes('y'));

    await store.clear();

    expect(await store.paths(), isEmpty);
    expect(files(), isEmpty);
  });
}
