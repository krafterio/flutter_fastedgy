/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';

void main() {
  test('titles a validation error through the catalog, each field with its message', () {
    final formatted = formatApiError({
      'detail': [
        {
          'loc': ['body', 'email'],
          'msg': 'Not an email',
          'type': 'value_error',
        },
      ],
    });

    expect(formatted.title, 'Validation error');
    expect(formatted.fieldErrors.single.field, 'email');
    expect(formatted.fieldErrors.single.message, 'Not an email');
  });

  test('names a field by its label in the metadata, and says what is about none apart', () {
    final formatted = formatApiError(
      {
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
        ],
      },
      fields: {
        'email': metaField('email', type: 'char', label: 'Email'),
        'tags': metaField('tags', type: 'json', label: 'Tags'),
      },
    );

    expect(formatted.fieldErrors.map((error) => error.field), [
      'email',
      'tags[0]',
    ]);
    expect(formatted.messages, ['Nothing changes', 'Too high']);
    expect(formatted.points, [
      'Nothing changes',
      'Too high',
      'Field Email: Not an email',
      'Field Tags: Too long',
    ]);
  });

  test('says a point alone as it is, several under the title in bullets', () {
    const alone = FormattedError(
      title: 'Validation error',
      fieldErrors: [
        FieldError(field: 'email', message: 'Not an email', type: ''),
      ],
    );
    const several = FormattedError(
      title: 'Validation error',
      fieldErrors: [
        FieldError(
          field: 'email',
          label: 'Email',
          message: 'Not an email',
          type: '',
        ),
      ],
      messages: ['Nothing changes'],
    );

    expect(alone.fullMessage, 'Field email: Not an email');
    expect(
      several.fullMessage,
      'Validation error\n• Nothing changes\n• Field Email: Not an email',
    );
    expect(const FormattedError(title: 'Locked').fullMessage, 'Locked');
  });
}
