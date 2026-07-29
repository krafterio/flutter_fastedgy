/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../theme/component_theme.dart';

/// Geometry of a document page: one centred text column that the editor's
/// blocks, its header and its footer all align on.
///
/// Layout rather than colour, so it stays its own object instead of folding
/// into `RichTextTheme` — how wide a page reads is a decision an application
/// makes about its content, not about its palette. It resolves through the same
/// mechanism all the same, because a page's header and its editor have to agree
/// on the column, and they are rarely built by the same widget.
@immutable
class DocumentLayout extends ComponentThemeData {
  final double contentWidth;
  final double horizontalPadding;

  /// Width reserved on the left of every block by the gutter (+ and drag grip),
  /// so its buttons hang in the margin instead of pushing the text.
  ///
  /// What it is actually given is [gutter], never more than the margin there is
  /// to hang in.
  final double gutterWidth;

  const DocumentLayout({
    this.contentWidth = 720,
    this.horizontalPadding = 56,
    this.gutterWidth = 42,
  });

  /// What a full-width document page uses.
  static const DocumentLayout standard = DocumentLayout();

  /// The layout in scope, or [standard].
  ///
  /// Derived from no token: how wide a page reads is a decision about content,
  /// and there is no role that could answer it. An application mounts a
  /// `ComponentTheme<DocumentLayout>` once, or a subtree mounts its own for a
  /// narrower column inside a panel.
  static DocumentLayout of(BuildContext context) {
    return ComponentTheme.maybeOf<DocumentLayout>(context) ?? standard;
  }

  /// What the editor and the header and footer it scrolls constrain themselves
  /// to — the same column, padding included.
  double get maxWidth => contentWidth + 2 * horizontalPadding;

  /// The gutter as it is really drawn.
  ///
  /// A gutter hangs in the margin, so it cannot be wider than one: asking for
  /// more than [horizontalPadding] would push every block off the column its
  /// header and footer sit on. A narrow page — a phone, where the margin is
  /// whatever the application's screens use — simply gets a narrow gutter.
  double get gutter =>
      gutterWidth < horizontalPadding ? gutterWidth : horizontalPadding;

  /// The editor's own padding: cut on the left by the gutter it hangs in, so
  /// block text still lines up with the header.
  EdgeInsets get editorPadding => EdgeInsets.only(
    left: horizontalPadding - gutter,
    right: horizontalPadding,
  );

  EdgeInsets sidePadding({double top = 0, double bottom = 0}) =>
      EdgeInsets.fromLTRB(horizontalPadding, top, horizontalPadding, bottom);

  DocumentLayout copyWith({
    double? contentWidth,
    double? horizontalPadding,
    double? gutterWidth,
  }) {
    return DocumentLayout(
      contentWidth: contentWidth ?? this.contentWidth,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      gutterWidth: gutterWidth ?? this.gutterWidth,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is DocumentLayout &&
        other.contentWidth == contentWidth &&
        other.horizontalPadding == horizontalPadding &&
        other.gutterWidth == gutterWidth;
  }

  @override
  int get hashCode => Object.hash(contentWidth, horizontalPadding, gutterWidth);
}
