/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// The theme engine (FastEdgyTheme, its roles, its component themes), the
/// glyphs, the interaction and responsive helpers and the full-screen image
/// viewer, on the widgets layer alone: no Material, no Cupertino. The
/// animated theme and its tween go by FastEdgyAnimatedTheme and
/// FastEdgyThemeDataTween here; ui.dart keeps their former names.
library;

export 'src/ui/theme/animated_theme.dart'
    show FastEdgyAnimatedTheme, FastEdgyThemeDataTween;
export 'src/ui/theme/breakpoints.dart';
export 'src/ui/theme/color_scheme.dart' show ColorRoles;
export 'src/ui/theme/component_theme.dart'
    show ComponentTheme, ComponentThemeData;
export 'src/ui/theme/scaling.dart' show AdaptiveScaling, Density;
export 'src/ui/theme/theme.dart' show FastEdgyTheme;
export 'src/ui/theme/theme_data.dart' show FastEdgyThemeData;
export 'src/ui/theme/typography.dart' show TypographyRoles;
export 'src/ui/icons.dart';
export 'src/ui/interaction.dart';
export 'src/ui/responsive.dart';
export 'src/ui/image/fullscreen_image_viewer.dart';
