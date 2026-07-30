/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';

/// Whether the clipboard holds anything worth offering to paste.
///
/// Kept rather than asked at each build because asking is asynchronous and a
/// button has to say whether it is live while it is being drawn. Starts as
/// true: a paste button greyed out because nothing has been read yet would be
/// wrong more often than right.
final richTextClipboardHasContent = ValueNotifier<bool>(true);

/// Asks the platform whether there is text to paste, without asking for the
/// text.
///
/// `hasStrings` and not `getData`, and this is the whole reason the value is
/// kept at all: reading the clipboard on iOS raises the system's "Allow paste?"
/// prompt, and a strip that read it to grey out a button would raise that
/// prompt every time it appeared. Asking whether there *is* something raises
/// nothing.
Future<void> refreshRichTextClipboard() async {
  try {
    richTextClipboardHasContent.value = await Clipboard.hasStrings();
  } on PlatformException {
    // A platform that will not answer is one where the button is better left
    // live: pressing it is then the only way to find out, which is what every
    // editor did before this.
    richTextClipboardHasContent.value = true;
  }
}
