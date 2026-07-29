/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The theme system is the one place a Material import would be contagious:
/// every package reads it, so pulling `material.dart` in here would drag
/// Material into all of them. A check is cheaper than a review that forgets.
void main() {
  test('nothing under src/ui/theme imports Material or Cupertino', () {
    final offenders = <String>[];

    for (final entity in Directory(
      'lib/src/ui/theme',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final source = entity.readAsStringSync();

      if (source.contains('package:flutter/material.dart') ||
          source.contains('package:flutter/cupertino.dart')) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
