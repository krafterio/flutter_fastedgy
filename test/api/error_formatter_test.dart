/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

HttpError _answered(Object? data) => HttpError(message: 'HTTP 422', data: data);

void main() {
  test('reads the reason the server names', () {
    expect(
      formatApiError(_answered({'detail': 'Too late'})).fullMessage,
      'Too late',
    );
    expect(
      formatApiError(_answered({'message': 'Locked'})).fullMessage,
      'Locked',
    );
  });

  test('names a field by its label in the metadata, and says what is about none apart', () {
    final formatted = formatApiError(
      _answered({
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'Not an email',
            'type': 'value_error',
          },
          {
            'loc': ['body', 'tags', 0],
            'msg': 'Too long',
            'type': 'value_error',
          },
          {
            'loc': ['body'],
            'msg': 'Nothing changes',
            'type': 'value_error',
          },
          {
            'loc': ['query', 'limit'],
            'msg': 'Too high',
            'type': 'value_error',
          },
          {'msg': 'Try again'},
        ],
      }),
      fields: {
        'email': metaField('email', type: 'char', label: 'Email'),
        'tags': metaField('tags', type: 'json', label: 'Tags'),
      },
    );

    expect(formatted.title, 'Validation error');
    expect(formatted.fieldErrors.map((error) => error.field), [
      'email',
      'tags[0]',
    ]);
    expect(formatted.messages, ['Nothing changes', 'Too high', 'Try again']);
    expect(formatted.points, [
      'Nothing changes',
      'Too high',
      'Try again',
      'Field Email: Not an email',
      'Field Tags: Too long',
    ]);
  });

  test('says a field the metadata do not name by its message alone', () {
    final formatted = formatApiError(
      _answered({
        'detail': [
          {
            'loc': ['body', 'secret'],
            'msg': 'Required',
            'type': 'missing',
          },
        ],
      }),
    );

    expect(formatted.fieldErrors.single.field, 'secret');
    expect(formatted.fullMessage, 'Required');
  });

  test('says a point alone as it is, several under the title in bullets', () {
    final message = formatValidationErrors(
      _answered({
        'detail': [
          {
            'loc': ['body', 'name'],
            'msg': 'Required',
            'type': 'missing',
          },
          {'msg': 'Too long'},
        ],
      }),
      fields: {'name': metaField('name', type: 'char', label: 'Name')},
    );

    expect(message, 'Validation error\n• Too long\n• Field Name: Required');
  });

  test('falls back on the wording it is given, then on its own', () {
    expect(
      formatValidationErrors(
        _answered({'detail': <Object?>[]}),
        defaultMessage: 'Export failed',
      ),
      'Export failed',
    );
    expect(
      formatValidationErrors(
        _answered({
          'detail': {'code': 'nope'},
        }),
      ),
      'An error occurred',
    );
    expect(
      formatValidationErrors(
        StateError('network down'),
        defaultMessage: 'Export failed',
      ),
      'Export failed',
    );
  });

  test('says nothing without an error', () {
    expect(formatValidationErrors(null), isNull);
  });
}
