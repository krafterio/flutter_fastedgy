/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
