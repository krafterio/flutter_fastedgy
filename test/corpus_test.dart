/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// This package held to the shared corpus, with the assertions every other
// implementation runs on the very same files. Without this the corpus would
// stop being an arbiter the day this package drifted.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'corpus_support.dart';

void main() {
  useCorpusServices();

  List<String> namesIn(Directory directory) =>
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.md'))
          .map((name) => name.substring(0, name.length - 3))
          .toList()
        ..sort();

  ({String markdown, Object? outline}) read(Directory directory, String name) => (
    markdown: File('${directory.path}/$name.md').readAsStringSync(),
    outline: jsonDecode(File('${directory.path}/$name.outline.json').readAsStringSync()),
  );

  final canonical = Directory(corpusDirectory);
  final lenient = Directory('$corpusDirectory/lenient');

  group('canonical corpus', () {
    for (final name in namesIn(canonical)) {
      final fixture = read(canonical, name);

      test('$name: reading gives the expected document', () {
        expect(outlineOf(corpusCodec.decode(fixture.markdown)), fixture.outline);
      });

      test('$name: writing gives the source back', () {
        expect(corpusCodec.encode(corpusCodec.decode(fixture.markdown)), fixture.markdown);
      });

      test('$name: a second round moves nothing', () {
        final once = corpusCodec.encode(corpusCodec.decode(fixture.markdown));

        expect(corpusCodec.encode(corpusCodec.decode(once)), once);
      });
    }
  });

  group('lenient corpus', () {
    for (final name in namesIn(lenient)) {
      final fixture = read(lenient, name);

      test('$name: reading gives the expected document', () {
        expect(outlineOf(corpusCodec.decode(fixture.markdown)), fixture.outline);
      });

      test('$name: what is rewritten from it is stable', () {
        final once = corpusCodec.encode(corpusCodec.decode(fixture.markdown));

        expect(corpusCodec.encode(corpusCodec.decode(once)), once);
      });
    }
  });
}
