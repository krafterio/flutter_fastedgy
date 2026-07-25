/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

MetadataField _field(
  String name,
  String type, {
  String? target,
  List<String>? targets,
}) => MetadataField(
  name: name,
  label: name,
  type: type,
  readonly: false,
  required: false,
  searchable: false,
  extra: false,
  filterOperators: const [],
  target: target,
  targets: targets,
);

MetadataModel _model(
  String name,
  String apiName,
  Map<String, MetadataField> fields,
) => MetadataModel(
  name: name,
  apiName: apiName,
  label: name,
  labelPlural: name,
  searchable: false,
  sortable: false,
  synchronizable: true,
  fields: fields,
);

final _metadatas = {
  'flow': _model('flow', 'flows', {
    'name': _field('name', 'char'),
    'project': _field('project', 'many2one', target: 'project'),
    'assignees': _field('assignees', 'many2many', target: 'user'),
    'details': _field('details', 'json'),
  }),
  'attachment': _model('attachment', 'attachments', {
    'name': _field('name', 'char'),
    'record': _field('record', 'reference', targets: ['flow', 'project']),
  }),
  'project': _model('project', 'projects', {'name': _field('name', 'char')}),
  'user': _model('user', 'users', {'name': _field('name', 'char')}),
};

void main() {
  group('TempIdMap', () {
    test('resolves a temporary id only within its own model', () {
      final map = TempIdMap();
      map.register('flow', -1, 42);
      map.register('attachment', -1, 100);

      expect(map.resolve('flow', -1), 42);
      expect(map.resolve('attachment', -1), 100);
      expect(map.resolve('project', -1), isNull);
    });

    test('remaps a to-one relation through its declared target', () {
      final map = TempIdMap();
      map.register('project', -7, 12);

      expect(map.remap({'project': -7}, 'flow', _metadatas), {'project': 12});
    });

    test('is the fix for overlapping per-model ids', () {
      // The exact scenario: one flow and three attachments created offline,
      // whose per-model sequences both start at -1. Substituting by value alone
      // would point every attachment at the attachment that took -1.
      final map = TempIdMap();
      map.register('flow', -1, 42);
      map.register('attachment', -1, 100);
      map.register('attachment', -2, 101);
      map.register('attachment', -3, 102);

      for (final tempId in [-1, -2, -3]) {
        final remapped =
            map.remap(
                  {
                    'name': 'file',
                    'record': {'model': 'flow', 'id': -1},
                  },
                  'attachment',
                  _metadatas,
                )
                as Map;

        expect(
          (remapped['record'] as Map)['id'],
          42,
          reason:
              'attachment $tempId must point at the flow, not an attachment',
        );
      }
    });

    test('reads a generic reference target from either spelling', () {
      final map = TempIdMap();
      map.register('flow', -1, 42);

      final read =
          map.remap(
                {
                  'record': {r'$model': 'flow', 'id': -1},
                },
                'attachment',
                _metadatas,
              )
              as Map;
      final write =
          map.remap(
                {
                  'record': {'model': 'flow', 'id': -1},
                },
                'attachment',
                _metadatas,
              )
              as Map;

      expect((read['record'] as Map)['id'], 42);
      expect((write['record'] as Map)['id'], 42);
    });

    test('leaves a reference pointing at another model untouched', () {
      final map = TempIdMap();
      map.register('flow', -1, 42);

      final remapped =
          map.remap(
                {
                  'record': {'model': 'project', 'id': -1},
                },
                'attachment',
                _metadatas,
              )
              as Map;

      // Same value, different model: it is not the flow's temporary id.
      expect((remapped['record'] as Map)['id'], -1);
    });

    test('remaps to-many relations in every accepted shape', () {
      final map = TempIdMap();
      map.register('user', -1, 7);
      map.register('user', -2, 8);

      expect(
        map.remap(
          {
            'assignees': [-1, -2, 5],
          },
          'flow',
          _metadatas,
        ),
        {
          'assignees': [7, 8, 5],
        },
      );

      expect(
        map.remap(
          {
            'assignees': [
              ['link', -1],
            ],
          },
          'flow',
          _metadatas,
        ),
        {
          'assignees': [
            ['link', 7],
          ],
        },
      );

      expect(
        map.remap(
          {
            'assignees': [
              [
                'set',
                [-1, -2],
              ],
            ],
          },
          'flow',
          _metadatas,
        ),
        {
          'assignees': [
            [
              'set',
              [7, 8],
            ],
          ],
        },
      );

      expect(
        map.remap(
          {
            'assignees': [
              {'id': -2, 'name': 'Ada'},
            ],
          },
          'flow',
          _metadatas,
        ),
        {
          'assignees': [
            {'id': 8, 'name': 'Ada'},
          ],
        },
      );
    });

    test('never touches a free-form JSON field', () {
      final map = TempIdMap();
      map.register('flow', -1, 42);

      // No declared target means no model to resolve against: guessing here
      // would corrupt values that merely happen to be negative.
      expect(
        map.remap(
          {
            'details': {'id': -1, 'delta': -1},
          },
          'flow',
          _metadatas,
        ),
        {
          'details': {'id': -1, 'delta': -1},
        },
      );
    });

    test('leaves an unknown field untouched', () {
      final map = TempIdMap();
      map.register('flow', -1, 42);

      expect(map.remap({'unknown': -1}, 'flow', _metadatas), {'unknown': -1});
    });

    test('is a no-op without metadata or model', () {
      final map = TempIdMap();
      map.register('flow', -1, 42);

      expect(map.remap({'project': -1}, 'flow', null), {'project': -1});
      expect(map.remap({'project': -1}, null, _metadatas), {'project': -1});
      expect(map.remap({'project': -1}, 'unknown', _metadatas), {
        'project': -1,
      });
    });

    test('is a no-op while empty', () {
      expect(TempIdMap().remap({'project': -1}, 'flow', _metadatas), {
        'project': -1,
      });
    });

    group('scopeOf', () {
      test('prefers the declared model', () {
        expect(
          TempIdMap.scopeOf('flow', '/anything', _metadatas, fallback: 'x'),
          'flow',
        );
      });

      test('resolves the model by api_name from the path', () {
        // What ApiModel does to find its own metadata, so a resource declaring
        // no model name still scopes on the metadata name a relation targets.
        expect(
          TempIdMap.scopeOf(null, '/acme/flows', _metadatas, fallback: 'x'),
          'flow',
        );
        expect(
          TempIdMap.scopeOf(null, '/attachments', _metadatas, fallback: 'x'),
          'attachment',
        );
      });

      test('falls back when nothing matches', () {
        expect(
          TempIdMap.scopeOf(null, '/unknown', _metadatas, fallback: 'ns'),
          'ns',
        );
        expect(TempIdMap.scopeOf(null, '/flows', null, fallback: 'ns'), 'ns');
      });
    });
  });
}
