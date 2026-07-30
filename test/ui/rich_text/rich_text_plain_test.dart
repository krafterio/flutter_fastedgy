/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('markdownToPlainText', () {
    test('nothing said is nothing to say', () {
      expect(markdownToPlainText(null), '');
      expect(markdownToPlainText(''), '');
      expect(markdownToPlainText('   \n\n  '), '');
    });

    test('the marks go, the words stay', () {
      expect(
        markdownToPlainText(
          '**gras** et *italique* et ~~barré~~ et ++souligné++ et `code`',
        ),
        'gras et italique et barré et souligné et code',
      );
    });

    test('a link reads as what it was called', () {
      expect(
        markdownToPlainText('Voir [Marmiton](https://marmiton.org/x) pour ça'),
        'Voir Marmiton pour ça',
      );
    });

    test('a mention keeps the name it names', () {
      expect(
        markdownToPlainText('Demande à [@Marie](/r/user/12) demain'),
        'Demande à @Marie demain',
      );
    });

    test('an image says nothing a line of text can hold', () {
      expect(
        markdownToPlainText('![photo](https://x/y.png) Regarde'),
        'Regarde',
      );
    });

    test('an address written as itself is the words it is', () {
      expect(
        markdownToPlainText('Rejoindre <https://teams.microsoft.com/l/42>'),
        'Rejoindre https://teams.microsoft.com/l/42',
      );
      expect(
        markdownToPlainText('Écrire à <marie.durand@example.org>'),
        'Écrire à marie.durand@example.org',
      );
    });

    test('what a block opens with is not what it says', () {
      expect(
        markdownToPlainText(
          '# Courses\n- [ ] pain\n- [x] lait\n1. sel\n> noté',
        ),
        'Courses pain lait sel noté',
      );
    });

    test('a fenced block gives up its rails, never its code', () {
      expect(
        markdownToPlainText('Avant\n```dart\nfinal x = 1;\n```\nAprès'),
        'Avant final x = 1; Après',
      );
    });

    test('a table reads as its cells', () {
      expect(markdownToPlainText('| A | B |\n|---|---|\n| 1 | 2 |'), 'A B 1 2');
    });

    test('a description off an external calendar is read as text', () {
      expect(
        markdownToPlainText('<p>Bonjour <b>Marie</b><br>À demain</p>'),
        'Bonjour Marie À demain',
      );
    });

    test('a stylesheet is taken out with what it holds', () {
      expect(
        markdownToPlainText(
          '<html><head><style>p { color: red; }</style></head>'
          '<body><p>Réunion</p></body></html>',
        ),
        'Réunion',
      );
    });

    test('an escaped character is the character it stands for', () {
      expect(
        markdownToPlainText(r'&Eacute;crire caf&eacute; &amp; th&eacute;'),
        'Écrire café & thé',
      );
      expect(markdownToPlainText('L&#39;heure&nbsp;: 9h'), "L'heure : 9h");
    });

    test('an entity nobody taught it is left where it stands', () {
      expect(markdownToPlainText('&trade; garanti'), '&trade; garanti');
    });

    test('an identifier is a word, not something in italics', () {
      expect(
        markdownToPlainText('Voir fichier_de_test_final et _vraiment_ lire'),
        'Voir fichier_de_test_final et vraiment lire',
      );
    });

    test('a language keeps the pluses it is named with', () {
      expect(
        markdownToPlainText('C++ et C++ au programme'),
        'C++ et C++ au programme',
      );
    });

    test('a marker somebody escaped is not a marker', () {
      expect(markdownToPlainText(r'\*pas en italique\*'), '*pas en italique*');
    });

    test('on several lines, the blocks keep lines of their own', () {
      expect(
        markdownToPlainText('# Courses\n\n- pain\n- lait', singleLine: false),
        'Courses\n\npain\nlait',
      );
    });
  });
}
