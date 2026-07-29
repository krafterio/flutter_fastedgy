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

  /// Width reserved on the left of every block by the hover gutter (+ and drag
  /// grip), so its buttons hang in the margin instead of pushing the text.
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

  /// The editor's own padding: cut on the left by the gutter it hangs in, so
  /// block text still lines up with the header.
  EdgeInsets get editorPadding => EdgeInsets.only(
    left: horizontalPadding - gutterWidth,
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
