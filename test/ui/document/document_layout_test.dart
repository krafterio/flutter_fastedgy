/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentLayout', () {
    test('one column, and everything aligns on it', () {
      const layout = DocumentLayout.standard;

      expect(
        layout.maxWidth,
        layout.contentWidth + 2 * layout.horizontalPadding,
      );
      expect(
        layout.editorPadding.left,
        layout.horizontalPadding - layout.gutterWidth,
        reason: 'the gutter hangs in the margin instead of pushing the text',
      );
      expect(layout.editorPadding.right, layout.horizontalPadding);
      expect(layout.sidePadding(top: 8, bottom: 4).top, 8);
      expect(layout.sidePadding(top: 8, bottom: 4).bottom, 4);
    });

    test('a margin narrower than the gutter keeps the column where it is', () {
      // What a phone asks for: the page lines up with the screen's own margin,
      // which is narrower than a gutter meant for a desktop page. The gutter
      // gives way — pushing the blocks off the column their header sits on
      // would be worse, and a negative padding asserts outright.
      final phone = DocumentLayout.standard.copyWith(horizontalPadding: 24);

      expect(phone.gutter, 24);
      expect(phone.editorPadding.left, 0);
      expect(phone.editorPadding.right, 24);
    });

    test('a margin with room to spare leaves the gutter its width', () {
      const page = DocumentLayout.standard;

      expect(page.gutter, page.gutterWidth);
    });

    test('copyWith narrows the column and the rest follows', () {
      final narrow = DocumentLayout.standard.copyWith(contentWidth: 500);

      expect(narrow.maxWidth, 500 + 2 * narrow.horizontalPadding);
      expect(narrow.gutterWidth, DocumentLayout.standard.gutterWidth);
    });

    testWidgets(
      'an application narrows the column once, for everything under it',
      (tester) async {
        late DocumentLayout header;
        late DocumentLayout editor;
        late DocumentLayout outside;

        final narrow = DocumentLayout.standard.copyWith(contentWidth: 500);

        await tester.pumpWidget(
          Column(
            children: [
              Builder(
                builder: (context) {
                  outside = DocumentLayout.of(context);

                  return const SizedBox();
                },
              ),
              ComponentTheme<DocumentLayout>(
                data: narrow,
                // A header and an editor are rarely built by the same widget:
                // resolving from the context is what keeps them on one column.
                child: Column(
                  children: [
                    Builder(
                      builder: (context) {
                        header = DocumentLayout.of(context);

                        return const SizedBox();
                      },
                    ),
                    Builder(
                      builder: (context) {
                        editor = DocumentLayout.of(context);

                        return const SizedBox();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        expect(header, narrow);
        expect(editor, narrow);
        expect(outside, DocumentLayout.standard);
      },
    );
  });
}
