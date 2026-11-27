/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/rich_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes the markdown of the editor as html', () {
    final html = markdownToHtml(
      '## Dîner\n\nÀ **20h**, avec ~~Paul~~ [Ada](https://example.io).\n\n- pain\n- vin',
    );

    expect(html, contains('<h2>Dîner</h2>'));
    expect(html, contains('<strong>20h</strong>'));
    expect(html, contains('<del>Paul</del>'));
    expect(html, contains('<a href="https://example.io">Ada</a>'));
    expect(html, contains('<li>pain</li>'));
  });

  test('carries no raw tag through', () {
    final html = markdownToHtml(
      'Bonjour <script>alert(1)</script>\n\n<iframe src="x"></iframe>',
    );

    expect(html, isNot(contains('<script>')));
    expect(html, isNot(contains('<iframe')));
    expect(html, contains('&lt;script&gt;'));
  });

  test('says nothing of nothing', () {
    expect(markdownToHtml(null), '');
    expect(markdownToHtml('  \n'), '');
  });
}
