/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show showLinkMenuCommand;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what counts as a link', () {
    test('a bare host is one, scheme or not', () {
      expect(isLinkable('kascade.io'), isTrue);
      expect(isLinkable('kascade.io/flows/42'), isTrue);
      expect(isLinkable('https://kascade.io'), isTrue);
      expect(isLinkable('  kascade.io  '), isTrue);
    });

    test('prose is not', () {
      expect(isLinkable(''), isFalse);
      expect(isLinkable('   '), isFalse);
      expect(isLinkable('deux mots'), isFalse);
      expect(isLinkable('kascade'), isFalse);
    });
  });

  group('how a link is stored', () {
    test('a bare host gets https, an explicit scheme is left alone', () {
      expect(normalizeLink('kascade.io'), 'https://kascade.io');
      expect(normalizeLink('  kascade.io/x '), 'https://kascade.io/x');
      expect(normalizeLink('http://kascade.io'), 'http://kascade.io');
    });
  });

  test(
    'the feature replaces the package item rather than adding a second one',
    () {
      final items = defaultRichTextFeatures.toolbarItems.where(
        (item) => item.id == LinkFeature.id,
      );

      expect(items, hasLength(1));
      expect(items.single.group, 4);
    },
  );

  test('every route to a link menu is ours', () {
    // Clicking a link is the one that bit: a pasted URL is autolinked when the
    // markdown is read back, and the package answered such clicks in English.
    expect(defaultRichTextFeatures.textSpanDecorator, isNotNull);

    final shortcuts = defaultRichTextFeatures.commandShortcuts.where(
      (event) => event.key == 'link menu',
    );

    // Cmd+K is ours, not the package's — every feature command is offered
    // before the standard ones, and the editor stops at the first handler that
    // reports the key handled.
    expect(shortcuts, hasLength(1));
    expect(shortcuts.single, same(linkShortcut));
    expect(shortcuts.single, isNot(same(showLinkMenuCommand)));
  });

  test('the link card speaks through the catalogs', () {
    final fr = jsonDecode(
      File('assets/translations/fr.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final en = jsonDecode(
      File('assets/translations/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    const keys = [
      'Link',
      'Add a link',
      'Edit link',
      'Title',
      'The text to show',
      'Paste or type a link',
      'Open',
      'Copy',
      'Remove',
      'Add',
    ];

    for (final key in keys) {
      expect(fr, contains(key));
      expect(en, contains(key));
    }
  });
}
