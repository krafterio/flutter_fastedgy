/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _arguments(String text) => {
  for (final match in RegExp(r'\{\w+\}').allMatches(text)) match[0]!,
};

void main() {
  final catalogs = {
    for (final file in Directory(
      'assets/translations',
    ).listSync().whereType<File>())
      file.uri.pathSegments.last.replaceAll('.json', ''):
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  };
  final keys = {for (final words in catalogs.values) ...words.keys};

  test('every catalog of the package translates every key', () {
    for (final MapEntry(key: language, value: words) in catalogs.entries) {
      expect(
        keys.difference(words.keys.toSet()),
        isEmpty,
        reason: 'missing in $language.json',
      );
    }
  });

  test('a translation keeps the named arguments of its key', () {
    for (final MapEntry(key: language, value: words) in catalogs.entries) {
      for (final MapEntry(:key, :value) in words.entries) {
        expect(
          _arguments(value as String),
          _arguments(key),
          reason: '$language.json: $key',
        );
      }
    }
  });
}
