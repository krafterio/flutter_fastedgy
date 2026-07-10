/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

class _Note extends BaseModel<_Note> {
  _Note(super.data);
}

class _Task extends BaseModel<_Task> {
  _Task(super.data);

  String? get name => getString('name');
}

void main() {
  group('generic reference helpers', () {
    test('reads a serialized record discriminated by \$model', () {
      final note = _Note({
        'id': 1,
        'record': {r'$model': 'task', 'id': 42, 'name': 'Faire les courses'},
      });

      expect(note.getReference('record'), isNotNull);
      expect(note.getReferenceModel('record'), 'task');
      expect(note.getReferenceId('record'), 42);
    });

    test('reads a staged write form', () {
      final note = _Note({
        'record': {'model': 'task', 'id': 7},
      });

      expect(note.getReferenceModel('record'), 'task');
      expect(note.getReferenceId('record'), 7);
    });

    test('returns null when the reference is empty', () {
      final note = _Note({'id': 1, 'record': null});

      expect(note.getReference('record'), isNull);
      expect(note.getReferenceModel('record'), isNull);
      expect(note.getReferenceId('record'), isNull);
    });

    test('getReferenceAs maps the record to a typed model per target', () {
      final note = _Note({
        'record': {r'$model': 'task', 'id': 42, 'name': 'Relever le courrier'},
      });

      final task = note.getReferenceAs('record', 'task', _Task.new);
      expect(task, isNotNull);
      expect(task!.name, 'Relever le courrier');

      expect(note.getReferenceAs('record', 'routine', _Task.new), isNull);
    });

    test('setReference stages the write form and null clears it', () {
      final note = _Note({});

      note.setReference('record', 'task', 42);
      expect(note.toJson()['record'], {'model': 'task', 'id': 42});

      note.setReference('record', null, null);
      expect(note.toJson()['record'], isNull);
    });
  });

  group('metadata targets', () {
    test('round trips the reference targets list', () {
      final field = MetadataField.fromJson({
        'name': 'record',
        'label': 'Enregistrement',
        'type': 'reference',
        'readonly': false,
        'required': true,
        'searchable': false,
        'extra': false,
        'filter_operators': ['=', '!=', 'in', 'not in'],
        'targets': ['task', 'calendar_event', 'routine'],
      });

      expect(field.type, 'reference');
      expect(field.targets, ['task', 'calendar_event', 'routine']);
      expect(field.toJson()['targets'], ['task', 'calendar_event', 'routine']);
    });

    test('targets stays null on non-reference fields', () {
      final field = MetadataField.fromJson({
        'name': 'name',
        'label': 'Nom',
        'type': 'string',
        'readonly': false,
        'required': true,
        'searchable': true,
        'extra': false,
        'filter_operators': ['='],
      });

      expect(field.targets, isNull);
    });
  });
}
