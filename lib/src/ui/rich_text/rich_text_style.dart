/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';

import '../interaction.dart';
import 'rich_text_theme.dart';
import 'rich_text_toolbar_theme.dart';

/// Turns a [RichTextTheme] into the style objects the underlying editor expects.
///
/// A derivation, not a table of values: everything here comes from the theme, so
/// an application that overrides a colour sees the editor, the view and the
/// blocks follow together.
class RichTextStyle {
  RichTextStyle._();

  /// How much smaller inline code reads than the text around it. Enough to tell
  /// a monospace run from its sentence without breaking the line's rhythm.
  static const double _inlineCodeDrop = 2;

  static EditorStyle editor(
    RichTextTheme theme, {
    required EdgeInsets padding,
    double? maxWidth,
    TextSpanDecoratorForAttribute? textSpanDecorator,
    TextStyle? text,
  }) {
    final blockText = text ?? theme.blockText;
    final configuration = TextStyleConfiguration(
      text: blockText,
      bold: blockText.copyWith(fontWeight: FontWeight.w600),
      code: blockText.copyWith(
        fontFamily: theme.monoFontFamily,
        fontSize: blockText.fontSize == null
            ? theme.fieldText.fontSize
            : blockText.fontSize! - _inlineCodeDrop,
        backgroundColor: theme.subtleSurface,
      ),
      href: blockText.copyWith(
        color: theme.link,
        decoration: TextDecoration.underline,
      ),
    );

    // The two are not two sets of colours: `.desktop` zeroes the magnifier, the
    // handle balls and the handle width, and turns the haptics off — a document
    // built with it under a thumb mounts the package's mobile selection service
    // and then draws every affordance it has at nothing. No handles to drag, no
    // magnifier to aim with, and a selection that reads as a grey rectangle
    // somebody moved with a mouse.
    if (hasHoverPointer) {
      return EditorStyle.desktop(
        textSpanDecorator: textSpanDecorator,
        padding: padding,
        maxWidth: maxWidth,
        cursorColor: theme.cursor,
        selectionColor: theme.selection,
        textStyleConfiguration: configuration,
      );
    }

    return EditorStyle.mobile(
      textSpanDecorator: textSpanDecorator,
      padding: padding,
      maxWidth: maxWidth,
      cursorColor: theme.cursor,
      dragHandleColor: theme.cursor,
      selectionColor: theme.selection,
      textStyleConfiguration: configuration,
    );
  }

  /// What the editor reserves above a selection for the floating toolbar: the
  /// package pins its top edge at `selection.top - floatingToolbarHeight`, so
  /// this is exactly how much anything else has to clear to sit above it.
  static const double toolbarHeight = 32.0;

  /// What the toolbar occupies once rendered, offset included. Only needed when
  /// it drops below the selection — approximate, unlike [toolbarHeight].
  static const double toolbarSpan = toolbarHeight + 44;

  static FloatingToolbarStyle toolbar(RichTextToolbarTheme theme) =>
      FloatingToolbarStyle(
        // Transparent: the surface under it is the package's own, shared with
        // every other floating card. A colour here would draw a second pill
        // inside the first.
        backgroundColor: const Color(0x00000000),
        toolbarActiveColor: theme.activeColor,
        toolbarIconColor: theme.iconColor,
      );

  static AppFlowyDropTargetStyle dropTarget(RichTextTheme theme) =>
      AppFlowyDropTargetStyle(color: theme.dropIndicator);

  /// The "/" menu keeps upstream's shape — it builds its own overlay and takes
  /// no builder — and wears the theme's colours.
  static SelectionMenuStyle slashMenu(RichTextTheme theme) {
    final label = theme.blockText.color ?? theme.ink;

    return SelectionMenuStyle(
      selectionMenuBackgroundColor: theme.surface,
      selectionMenuItemTextColor: label,
      selectionMenuItemIconColor: theme.mutedText,
      selectionMenuItemSelectedTextColor: theme.ink,
      selectionMenuItemSelectedIconColor: theme.ink,
      selectionMenuItemSelectedColor: theme.selection,
      selectionMenuUnselectedLabelColor: label,
      selectionMenuDividerColor: theme.subtleBorder,
      selectionMenuLinkBorderColor: theme.strongBorder,
      selectionMenuInvalidLinkColor: theme.danger,
      selectionMenuButtonColor: theme.ink,
      selectionMenuButtonTextColor: label,
      selectionMenuButtonIconColor: theme.mutedText,
      selectionMenuButtonBorderColor: theme.border,
      selectionMenuTabIndicatorColor: theme.ink,
    );
  }

  /// The editor's overlay inherits the ambient theme, so the "/" menu labels
  /// render in the host application's button font unless it is overridden here.
  static ThemeData overlayTheme(BuildContext context, RichTextTheme theme) =>
      Theme.of(context).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: theme.fieldText.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      );
}
