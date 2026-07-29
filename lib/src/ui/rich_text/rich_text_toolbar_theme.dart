/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../interaction.dart';
import '../theme/component_theme.dart';
import 'rich_text_theme.dart';

/// How the strip of formatting actions is drawn, and where it stands.
///
/// Its own theme rather than a corner of [RichTextTheme]: what a strip of
/// buttons measures is a decision about a control, and nothing else in the
/// stack reads one.
///
/// The metrics come in two sets and the platform picks — a pointer aims at a
/// 28-pixel button, a thumb misses it. An application overriding one value
/// keeps the rest of whichever set it landed in.
@immutable
class RichTextToolbarTheme extends ComponentThemeData {
  /// How tall the strip stands.
  ///
  /// Also what anything placing itself clear of the toolbar has to clear, so a
  /// taller one pushes the cards that open under a selection further down.
  final double height;

  /// The side of one button — what there is to hit.
  final double itemSize;

  /// The glyph inside it.
  final double iconSize;

  /// Between two buttons of the same group.
  final double itemSpacing;

  /// Between the surface and the buttons.
  final EdgeInsets padding;

  /// Left at the foot of the page, between the last block and a docked strip.
  ///
  /// The strip already stands beside the document rather than over it, so this
  /// is not room the content needs — it is the room it deserves: a last line
  /// ending flush against a row of buttons reads as one of them.
  ///
  /// Scrolls with the document, the way a list's bottom padding does, so it
  /// costs the page nothing while there is more to read.
  final double contentGap;

  /// What a button that is on wears — the bold one over bold text.
  final Color activeColor;

  /// What the others wear.
  final Color iconColor;

  /// The surface the strip sits on.
  ///
  /// Floating, it is the one every card shares, so a toolbar and a mention list
  /// read as the same family. Docked, it is flush against the bottom of the
  /// screen: nothing floats there, so it carries no shadow and no rounding —
  /// only a rule telling it apart from the text above.
  final BoxDecoration surface;

  /// Pinned above the keyboard rather than floating over the selection.
  ///
  /// Null follows the platform: a floating strip is a pointer's idea — it sits
  /// where the words are because a mouse is already there. Under a thumb it
  /// covers the line being worked on and moves every time the selection does,
  /// so a touch platform docks it and leaves the text alone.
  final bool? docked;

  const RichTextToolbarTheme({
    required this.height,
    required this.itemSize,
    required this.iconSize,
    required this.itemSpacing,
    required this.activeColor,
    required this.iconColor,
    required this.surface,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
    this.contentGap = 16,
    this.docked,
  });

  /// Derived from the roles, so an application that supplies no toolbar theme
  /// still gets one that matches everything else it floats — and metrics that
  /// match how it is going to be aimed at.
  factory RichTextToolbarTheme.from(RichTextTheme theme, {bool? docked}) {
    final touch = docked ?? _touchPlatform;

    return RichTextToolbarTheme(
      height: touch ? 52 : 36,
      itemSize: touch ? 40 : 28,
      iconSize: touch ? 22 : 18,
      itemSpacing: touch ? 8 : 2,
      contentGap: touch ? 16 : 0,
      activeColor: theme.ink,
      iconColor: theme.mutedText,
      surface: touch
          ? BoxDecoration(
              color: theme.surface,
              border: Border(top: BorderSide(color: theme.subtleBorder)),
            )
          : theme.floatingSurface,
      docked: docked,
    );
  }

  static bool get _touchPlatform => !hasHoverPointer;

  /// Whether this toolbar docks, the platform answering when nobody said.
  bool get isDocked => docked ?? _touchPlatform;

  static RichTextToolbarTheme of(BuildContext context) =>
      ComponentTheme.maybeOf<RichTextToolbarTheme>(context) ??
      RichTextToolbarTheme.from(RichTextTheme.of(context));

  RichTextToolbarTheme copyWith({
    double? height,
    double? itemSize,
    double? iconSize,
    double? itemSpacing,
    EdgeInsets? padding,
    double? contentGap,
    Color? activeColor,
    Color? iconColor,
    BoxDecoration? surface,
    bool? docked,
  }) => RichTextToolbarTheme(
    height: height ?? this.height,
    itemSize: itemSize ?? this.itemSize,
    iconSize: iconSize ?? this.iconSize,
    itemSpacing: itemSpacing ?? this.itemSpacing,
    padding: padding ?? this.padding,
    contentGap: contentGap ?? this.contentGap,
    activeColor: activeColor ?? this.activeColor,
    iconColor: iconColor ?? this.iconColor,
    surface: surface ?? this.surface,
    docked: docked ?? this.docked,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is RichTextToolbarTheme &&
        other.height == height &&
        other.itemSize == itemSize &&
        other.iconSize == iconSize &&
        other.itemSpacing == itemSpacing &&
        other.padding == padding &&
        other.contentGap == contentGap &&
        other.activeColor == activeColor &&
        other.iconColor == iconColor &&
        other.surface == surface &&
        other.docked == docked;
  }

  @override
  int get hashCode => Object.hash(
    height,
    itemSize,
    iconSize,
    itemSpacing,
    padding,
    contentGap,
    activeColor,
    iconColor,
    surface,
    docked,
  );
}
