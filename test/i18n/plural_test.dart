/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'outside a localized application, a plural shows its key with the number',
    () {
      expect(
        plural('{} jours restants pour {name}', 3, {'name': 'Léa'}),
        '3 jours restants pour Léa',
      );
    },
  );
}
