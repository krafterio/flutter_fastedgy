/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a document mounted next to a page keeps the page its gutter', () {
    final page = richTextBlocks(
      features: defaultRichTextFeatures,
      blockActions: (blockContext, builder) => const SizedBox.shrink(),
    );

    // What a message rendered under the page asks for: the same blocks, with
    // nothing hanging in their margin.
    richTextBlocks(features: defaultRichTextFeatures);

    for (final type in [
      BulletedListBlockKeys.type,
      NumberedListBlockKeys.type,
      TodoListBlockKeys.type,
    ]) {
      expect(page[type]!.showActions(Node(type: type)), isTrue, reason: type);
    }
  });
}
