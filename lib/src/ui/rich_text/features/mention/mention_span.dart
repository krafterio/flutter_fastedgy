/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';

import '../../rich_text_theme.dart';
import 'mention_address.dart';
import 'mention_popover.dart';

/// What a run carries when it is a mention rather than words.
const mentionAttribute = 'mention';

/// The single character a mention occupies in the text.
///
/// U+FFFC is what a [WidgetSpan] occupies in a painted paragraph: a mention
/// stored as one character and drawn as one widget keeps the delta and the
/// painter counting the same, so every caret offset after it stays right. It is
/// also why the caret can never land inside a mention — there is no inside, and
/// one backspace takes the whole thing.
const mentionPlaceholder = '￼';

/// A chip breathes barely more than the words around it.
const _chipPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 1);

/// A record named in a document.
///
/// The address is the record's, never the view's: a flow moved to another
/// project is the same flow, and the mention still points at it.
class Mention {
  final MentionAddress address;

  /// What is drawn, trigger included — `@François`, `#KAS-42`. It is a copy of
  /// what the record was called when the mention was written, which is also
  /// what markdown carries and what the agent reads.
  final String label;

  const Mention({required this.address, required this.label});

  Map<String, dynamic> toJson() => {
    'address': address.uri.toString(),
    'label': label,
  };

  /// Null for anything that is not one — the attribute absent, or holding
  /// something no longer readable.
  static Mention? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }

    final label = value['label'];
    final uri = value['address'] is String
        ? Uri.tryParse(value['address'] as String)
        : null;
    final address = uri == null ? null : mentionAddressing?.decode(uri);

    return address == null || label is! String
        ? null
        : Mention(address: address, label: label);
  }
}

/// The mention a run carries, or null when it carries words.
Mention? mentionOf(TextInsert text) =>
    Mention.fromJson(text.attributes?[mentionAttribute]);

/// The run that writes [mention] into a document.
Delta mentionRun(Mention mention) => Delta()
  ..insert(
    mentionPlaceholder,
    attributes: {mentionAttribute: mention.toJson()},
  );

/// Keeps a mention from bleeding onto what is typed against it.
///
/// The editor gives a typed character the attributes of the one before it —
/// that is how a word typed at the end of a bold run comes out bold. A mention
/// must be the exception: the character would join its run, the run is drawn as
/// a single chip, and so the letter would simply vanish and the caret would sit
/// stuck against the tag with nothing happening.
///
/// The package keeps a list of attributes exempt from that rule, which is how
/// `href` already behaves — typing after a link does not extend the link. This
/// puts the mention on it. Idempotent, and called wherever a [MentionSources]
/// is built, so no app has to remember to.
void keepMentionsWhole() {
  if (!AppFlowyRichTextKeys.partialSliced.contains(mentionAttribute)) {
    AppFlowyRichTextKeys.partialSliced.add(mentionAttribute);
  }
}

/// Draws a mention as the chip it is rather than as the character it is stored
/// as.
///
/// The only decorator of the editor to return something other than a
/// [TextSpan], which is what buys the padding and the rounded corners: a
/// [TextStyle] background is a paint, and a paint has no shape.
InlineSpan mentionTextSpanDecorator(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final mention = mentionOf(text);

  return mention == null
      ? before
      : WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          // The chip is a widget, so it inherits none of the run's style: the
          // size it reads at is taken from the editor it stands in — a page's
          // text or a field's — rather than fixed to one of them.
          child: MentionChip(mention: mention, textStyle: before.style),
        );
}

/// A mention, drawn — and what answers a click on it.
class MentionChip extends StatelessWidget {
  final Mention mention;

  /// The text the mention stands in. Null reads at a page's size.
  final TextStyle? textStyle;

  const MentionChip({required this.mention, super.key, this.textStyle});

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Its own card rather than the record's page: a mention is read in
        // passing, and leaving the document to find out who was named is the
        // one thing worth not doing. The card carries the way out.
        onTap: () => showMentionPopover(context, mention),
        child: Container(
          padding: _chipPadding,
          decoration: BoxDecoration(
            color: theme.selection,
            borderRadius: theme.chipRadius,
          ),
          child: Text(
            mention.label,
            // Reads at the size of the text it stands in, and tighter than it:
            // the chip adds its own height through the padding, and a mention
            // on a full line's leading would push its line apart.
            style: (textStyle ?? theme.blockText).copyWith(
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: theme.ink,
            ),
          ),
        ),
      ),
    );
  }
}
