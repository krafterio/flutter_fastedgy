/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:appflowy_editor/appflowy_editor.dart' show EditorStyle;
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  EditorStyle styleOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;

    return RichTextStyle.editor(
      RichTextTheme.fallback,
      padding: EdgeInsets.zero,
    );
  }

  group('le style que l\'éditeur reçoit', () {
    test('sous un doigt, les poignées et la loupe existent', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        final style = styleOn(platform);

        expect(
          style.mobileDragHandleBallSize,
          isNot(Size.zero),
          reason: '$platform',
        );
        expect(
          style.mobileDragHandleWidth,
          greaterThan(0),
          reason: '$platform',
        );
        expect(style.magnifierSize, isNot(Size.zero), reason: '$platform');
      }
    });

    test('sous une souris, elles n\'ont pas lieu d\'être', () {
      final style = styleOn(TargetPlatform.macOS);

      expect(style.mobileDragHandleBallSize, Size.zero);
      expect(style.magnifierSize, Size.zero);
    });

    test('et les couleurs du thème valent des deux côtés', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final style = styleOn(platform);

        expect(
          style.cursorColor,
          RichTextTheme.fallback.cursor,
          reason: '$platform',
        );
        expect(
          style.selectionColor,
          RichTextTheme.fallback.selection,
          reason: '$platform',
        );
      }
    });
  });
}
