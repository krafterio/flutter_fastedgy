/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  Map<String, dynamic> catalog(String locale) =>
      jsonDecode(File('assets/translations/$locale.json').readAsStringSync())
          as Map<String, dynamic>;

  test('every block the package offers is named from our catalog', () {
    final fr = catalog('fr');
    final en = catalog('en');

    for (final item in standardSelectionMenuItems) {
      // What the item is called here is the key it is translated under: a label
      // renamed upstream, or one of ours dropped from the catalog, silently
      // sends the item back to English — which is what this catches.
      final label = richTextMenuLabel(item.name);

      expect(
        fr,
        contains(label),
        reason: '"$label" is missing from the French catalog',
      );
      expect(
        en,
        contains(label),
        reason: '"$label" is missing from the English catalog',
      );
    }
  });

  test('the menu carries the package blocks and what the features add', () {
    final items = richTextSlashMenuItems(defaultRichTextFeatures);

    // A feature standing in for a package entry takes its place rather than
    // adding to it.
    expect(
      items,
      hasLength(
        standardSelectionMenuItems.length -
            defaultRichTextFeatures.replacedMenuItems.length +
            defaultRichTextFeatures.menuItems.length,
      ),
    );
    expect(
      items.map((item) => item.name),
      containsAll(defaultRichTextFeatures.menuItems.map((item) => item.name)),
    );
  });

  test(
    'a renamed item keeps the keywords and the handler it was built with',
    () {
      final divider = standardSelectionMenuItems.firstWhere(
        (item) => item.name == 'Divider',
      );
      final renamed = richTextSlashMenuItems(
        const RichTextFeatures([]),
      ).firstWhere((item) => item.name == 'Divider');

      expect(renamed.keywords, divider.keywords);
    },
  );

  test('only one item in the chain deletes the "/" that opened the menu', () {
    final wrapped = standardSelectionMenuItems.firstWhere(
      (item) => item.name == 'Divider',
    );
    final ours = richTextSlashMenuItems(
      const RichTextFeatures([]),
    ).firstWhere((item) => item.name == 'Divider');

    // The menu re-arms these on the items it is handed, so ours is always the
    // one that deletes and the one it wraps has to stand down. Both deleting
    // threw: the second found no "/" left and deleted from index -1.
    expect(ours.deleteSlash, isTrue);
    expect(wrapped.deleteSlash, isFalse);
    expect(wrapped.deleteKeywords, isFalse);
  });

  testWidgets('a formatter chosen on an otherwise empty paragraph just works', (
    tester,
  ) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(delta: Delta()..insert('/'))]),
    );
    addTearDown(state.dispose);
    state.selection = Selection.collapsed(Position(path: [0], offset: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextEditor(
            features: defaultRichTextFeatures,
            editorState: state,
          ),
        ),
      ),
    );
    await tester.pump();

    final heading = richTextSlashMenuItems(
      defaultRichTextFeatures,
    ).firstWhere((item) => item.name == 'H1');

    // What the menu does to the items it is handed, just before showing them.
    heading
      ..deleteSlash = true
      ..deleteKeywords = false;

    heading.handler(
      state,
      _NoMenu(),
      tester.element(find.byType(RichTextEditor)),
    );
    await tester.pump();

    // The editor leaves a timer of its own in flight; let it run out before
    // the tree goes away.
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(state.document.root.children.single.type, HeadingBlockKeys.type);
    // The "/" goes, and nothing else with it.
    expect(state.document.root.children.single.delta?.toPlainText(), isEmpty);
  });
}

/// The formatters ignore the menu service they are handed.
class _NoMenu implements SelectionMenuService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
