/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

const _oneEmojiPerColorFont = '🏁✅👑🎁🎡🍅🌊👦👋';

/// Loads the Noto Color Emoji fonts on the web before Noto Sans Symbols 2 draws an emoji in black for good.
void preloadColorEmoji() {
  if (!kIsWeb) return;
  TextPainter(
      text: const TextSpan(text: _oneEmojiPerColorFont),
      textDirection: TextDirection.ltr,
    )
    ..layout()
    ..dispose();
}
