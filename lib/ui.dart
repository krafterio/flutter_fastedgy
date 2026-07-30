/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// The UI module of flutter_fastedgy: headless widgets and the theme system
/// they draw with.
///
/// Kept out of `flutter_fastedgy.dart` on purpose — an application that only
/// talks to a server never pays for a widget it does not mount.
library;

// Theme — the engine only: what carries a theme and how one is found. A module
// declares its own beside its widgets.
export 'src/ui/theme/animated_theme.dart' show AnimatedTheme, ThemeDataTween;
export 'src/ui/theme/color_scheme.dart' show ColorRoles;
export 'src/ui/theme/component_theme.dart'
    show ComponentTheme, ComponentThemeData;
export 'src/ui/theme/scaling.dart' show AdaptiveScaling, Density;
export 'src/ui/theme/theme.dart' show FastEdgyTheme;
export 'src/ui/theme/theme_data.dart' show FastEdgyThemeData;
export 'src/ui/theme/typography.dart' show TypographyRoles;

// Rich text
export 'src/ui/rich_text/features/code_block/code_block_component.dart';
export 'src/ui/rich_text/features/code_block/code_block_feature.dart';
export 'src/ui/rich_text/features/code_block/code_block_shortcuts.dart';
export 'src/ui/rich_text/features/code_block/code_block_theme.dart';
export 'src/ui/rich_text/features/image/image_component.dart';
export 'src/ui/rich_text/features/image/image_feature.dart';
export 'src/ui/rich_text/features/image/image_markdown.dart';
export 'src/ui/rich_text/features/image/image_menu.dart';
export 'src/ui/rich_text/features/image/image_source.dart';
export 'src/ui/rich_text/features/image/image_store.dart';
export 'src/ui/rich_text/features/link/link_feature.dart';
export 'src/ui/rich_text/features/link/link_gestures.dart';
export 'src/ui/rich_text/features/link/link_markdown.dart';
export 'src/ui/rich_text/features/link/link_menu.dart';
export 'src/ui/rich_text/features/mention/mention_address.dart';
export 'src/ui/rich_text/features/mention/mention_controller.dart';
export 'src/ui/rich_text/features/mention/mention_feature.dart';
export 'src/ui/rich_text/features/mention/mention_markdown.dart';
export 'src/ui/rich_text/features/mention/mention_menu.dart';
export 'src/ui/rich_text/features/mention/mention_options.dart';
export 'src/ui/rich_text/features/mention/mention_popover.dart';
export 'src/ui/rich_text/features/mention/mention_preview.dart';
export 'src/ui/rich_text/features/mention/mention_source.dart';
export 'src/ui/rich_text/features/mention/mention_span.dart';
export 'src/ui/rich_text/features/paragraph_feature.dart';
export 'src/ui/rich_text/features/plus_underline_feature.dart';
export 'src/ui/rich_text/features/table/table_component.dart';
export 'src/ui/rich_text/features/table/table_feature.dart';
export 'src/ui/rich_text/features/table/table_handle.dart';
export 'src/ui/rich_text/features/table/table_markdown.dart';
export 'src/ui/rich_text/features/todo_list_feature.dart';
export 'src/ui/rich_text/rich_text_action.dart';
export 'src/ui/rich_text/rich_text_action_bar.dart';
export 'src/ui/rich_text/rich_text_blank.dart';
export 'src/ui/rich_text/rich_text_blocks.dart';
export 'src/ui/rich_text/rich_text_clipboard.dart';
export 'src/ui/rich_text/rich_text_codec.dart';
export 'src/ui/rich_text/rich_text_controls.dart';
export 'src/ui/rich_text/rich_text_diff.dart';
export 'src/ui/rich_text/rich_text_editor.dart';
export 'src/ui/rich_text/rich_text_feature.dart';
export 'src/ui/rich_text/rich_text_features.dart';
export 'src/ui/rich_text/rich_text_focus.dart';
export 'src/ui/icons.dart';
export 'src/ui/interaction.dart';
export 'src/ui/rich_text/rich_text_nesting.dart';
export 'src/ui/rich_text/rich_text_paste.dart';
export 'src/ui/rich_text/rich_text_plain.dart';
export 'src/ui/rich_text/rich_text_popover.dart';
export 'src/ui/rich_text/rich_text_markdown.dart';
export 'src/ui/rich_text/rich_text_menu.dart';
export 'src/ui/rich_text/rich_text_shortcuts.dart';
export 'src/ui/rich_text/rich_text_style.dart';
export 'src/ui/rich_text/rich_text_theme.dart' show RichTextTheme;
export 'src/ui/rich_text/rich_text_toolbar.dart';
export 'src/ui/rich_text/rich_text_touch_menu.dart';
export 'src/ui/rich_text/rich_text_toolbar_theme.dart';
export 'src/ui/rich_text/rich_text_viewer.dart';

// Images
export 'src/ui/image/fullscreen_image_viewer.dart';

// Documents
export 'src/ui/document/document_cover.dart';
export 'src/ui/document/document_editor.dart';
export 'src/ui/document/document_gutter.dart';
export 'src/ui/document/document_layout.dart' show DocumentLayout;
export 'src/ui/document/document_viewer.dart';
