/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What an application compiles of Material and Cupertino through this
/// package is decided by the entry point it imports. Material and Cupertino
/// stay behind the entry points made for them: a check walks every import
/// rather than trusting a review to see one more.
const _forbidden = [
  'package:material_ui/',
  'package:cupertino_ui/',
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
];

/// The entry points an application imports to get no Material and no
/// Cupertino from the package.
const _free = [
  'core.dart',
  'theme.dart',
  'interaction.dart',
  'list.dart',
  'query.dart',
  'responsive.dart',
  'testing.dart',
  'workspace.dart',
];

/// The entry points made to carry them, each the only door to its own.
const _onDemand = {
  'material.dart': ['package:material_ui/'],
  'cupertino.dart': ['package:cupertino_ui/'],
  'rich_text.dart': ['package:material_ui/', 'package:flutter/material.dart'],
};

/// The historical entry points, which keep giving what they gave, Material
/// and Cupertino included.
const _historical = ['flutter_fastedgy.dart', 'ui.dart'];

final _directive = RegExp(r'^\s*(?:import|export)\s+[^;]*;', multiLine: true);
final _uri = RegExp(r"""['"]([^'"]+)['"]""");

/// The URIs a library imports or exports, the conditional ones included.
List<String> _urisOf(String path) => [
  for (final directive in _directive.allMatches(File(path).readAsStringSync()))
    for (final uri in _uri.allMatches(directive.group(0)!)) uri.group(1)!,
];

/// The package's own libraries an entry point reaches, by their path.
Set<String> _reached(String entryPoint) {
  final seen = <String>{};
  final pending = ['lib/$entryPoint'];

  while (pending.isNotEmpty) {
    final path = File(pending.removeLast()).absolute.path;

    if (!seen.add(path)) {
      continue;
    }

    for (final uri in _urisOf(path)) {
      if (uri.startsWith('package:flutter_fastedgy/')) {
        pending.add('lib/${uri.substring('package:flutter_fastedgy/'.length)}');
      } else if (!uri.contains(':')) {
        pending.add(File(path).parent.uri.resolve(uri).toFilePath());
      }
    }
  }

  return seen;
}

/// Which of [prefixes] the libraries of [paths] import, by library.
Map<String, List<String>> _importing(
  Iterable<String> paths,
  List<String> prefixes,
) => {
  for (final path in paths)
    if (_urisOf(path).where((uri) => prefixes.any(uri.startsWith)).toList()
        case final hits when hits.isNotEmpty)
      path.substring(path.indexOf('/lib/') + 1): hits,
};

void main() {
  test('names every entry point of the package', () {
    final entryPoints = [
      for (final entity in Directory('lib').listSync())
        if (entity is File && entity.path.endsWith('.dart'))
          entity.uri.pathSegments.last,
    ];

    expect(entryPoints.toSet(), {..._free, ..._onDemand.keys, ..._historical});
  });

  for (final entryPoint in _free) {
    test('reaches neither Material nor Cupertino from $entryPoint', () {
      expect(_importing(_reached(entryPoint), _forbidden), isEmpty);
    });
  }

  for (final MapEntry(key: entryPoint, value: own) in _onDemand.entries) {
    test(
      'carries ${own.join(' and ')} through $entryPoint, and nothing else of them',
      () {
        final reached = _reached(entryPoint);
        final others = _forbidden
            .where((prefix) => !own.any(prefix.startsWith))
            .toList();

        expect(_importing(reached, own), isNotEmpty);
        expect(_importing(reached, others), isEmpty);
      },
    );
  }

  test('keeps every library importing Material or Cupertino behind an entry point made for them', () {
    final behind = {
      for (final entryPoint in _onDemand.keys) ..._reached(entryPoint),
    };
    final everywhere = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.absolute.path,
    ];

    expect(
      _importing(
        everywhere.where((path) => !behind.contains(path)),
        _forbidden,
      ),
      isEmpty,
    );
  });
}
