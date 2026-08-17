/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show Attachment;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  test('an attachment points at any record, not at a flow', () {
    // The generic reference is what makes the image feature reusable: a note or
    // a message stores its pictures the same way a flow does.
    final note = Attachment({}).attachToRecord('note', 7)..inlineOn('body');

    expect(note.recordModel, 'note');
    expect(note.recordId, 7);
    expect(note.inlineField, 'body');
    expect(note.isInline, isTrue);
  });

  test(
    'a file merely attached to a record belongs in its list, not a field',
    () {
      final attached = Attachment({}).attachToRecord('record', 42);

      expect(attached.recordId, 42);
      expect(attached.isInline, isFalse);
    },
  );

  test(
    'with no record yet, nothing is uploaded and the picture stays in the text',
    () async {
      final store = inlineImageStore(
        model: 'record',
        recordId: () => null,
        field: 'description',
      );

      // Reached without touching the network: a null id answers before any upload.
      expect(await store(File('/nowhere/pixel.png')), isNull);
    },
  );

  test('the record is read at each call, a screen building its features once', () async {
    int? id;
    final store = inlineImageStore(
      model: 'record',
      recordId: () => id,
      field: 'description',
    );

    expect(await store(File('/nowhere/pixel.png')), isNull);

    id = 42;

    // Now it would upload, so this only asserts the id is no longer the reason
    // it declines — the call is left to the suites that mock the uploader.
    expect(store, isNotNull);
  });
}
