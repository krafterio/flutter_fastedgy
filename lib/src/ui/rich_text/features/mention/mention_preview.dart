/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

/// What a mention says of its record when it is clicked.
///
/// A shape rather than a widget, so the four kinds read alike however
/// differently they are made: the card that draws this is written once, and a
/// source only has to say what its record *is*.
class MentionPreview {
  final String title;

  /// One line under the title — an address, a project, whatever names the
  /// record's place rather than the record.
  final String? subtitle;

  /// Avatar or icon, shown ahead of the title.
  final Widget? leading;

  /// What is worth knowing at a glance, as label and value: a flow's status and
  /// its due date, a project's flow count. Kept short — this is a card, not a
  /// screen.
  final List<(String label, String value)> facts;

  const MentionPreview({
    required this.title,
    this.subtitle,
    this.leading,
    this.facts = const [],
  });
}

/// What stands ahead of a title, in the only two sizes the card draws.
enum MentionLeading {
  none,

  /// A small glyph, as a flow or a note wears.
  icon,

  /// A picture of somebody, which is twice the size and round.
  avatar,
}

/// The card a kind of mention settles on, declared so it can be drawn before
/// the record has been read.
///
/// A skeleton is only worth it where it holds the shape of what replaces it:
/// a member's card is a face and one line, a flow's is an icon and three facts,
/// and standing in with the wrong one trades a blank card for a jump. The title
/// is not in here because every card has one, whatever the kind.
class MentionPreviewShape {
  final MentionLeading leading;

  /// Whether a line sits under the title.
  final bool subtitle;

  /// How many rows of fact the card settles on. The most it ever shows: a
  /// record missing one comes back a row shorter, which reads as an answer.
  final int facts;

  const MentionPreviewShape({
    this.leading = MentionLeading.none,
    this.subtitle = false,
    this.facts = 0,
  });

  /// What a kind of mention with no card at all is drawn as.
  static const none = MentionPreviewShape();
}
