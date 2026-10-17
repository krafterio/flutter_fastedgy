/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('addRedirect', () {
    test('carries the page, its query included', () {
      expect(
        addRedirect(Uri.parse('/w/acme/notes/12?list=3'), '/login'),
        '/login?redirect=%2Fw%2Facme%2Fnotes%2F12%3Flist%3D3',
      );
    });

    test('keeps the query of the location', () {
      expect(
        addRedirect(Uri.parse('/w/acme'), '/login?mode=short'),
        '/login?mode=short&redirect=%2Fw%2Facme',
      );
    });
  });

  group('getRedirect', () {
    test('reads back the page addRedirect carries', () {
      final current = Uri.parse('/w/acme/notes/12?list=3');

      expect(
        getRedirect(Uri.parse(addRedirect(current, '/login')), '/'),
        '/w/acme/notes/12?list=3',
      );
    });

    test('falls back without a redirect', () {
      expect(getRedirect(Uri.parse('/login'), '/home'), '/home');
    });

    test('follows only a page of the app', () {
      for (final redirect in [
        'https://example.com/w/acme',
        '//example.com/w/acme',
        'w/acme',
        '',
      ]) {
        final current = Uri(
          path: '/login',
          queryParameters: {'redirect': redirect},
        );

        expect(getRedirect(current, '/'), '/', reason: redirect);
      }
    });
  });
}
