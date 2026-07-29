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

// Theme
export 'src/ui/theme/animated_theme.dart' show AnimatedTheme, ThemeDataTween;
export 'src/ui/theme/color_scheme.dart' show ColorRoles;
export 'src/ui/theme/component_theme.dart'
    show ComponentTheme, ComponentThemeData;
export 'src/ui/theme/scaling.dart' show AdaptiveScaling, Density;
export 'src/ui/theme/theme.dart' show FastEdgyTheme;
export 'src/ui/theme/theme_data.dart' show FastEdgyThemeData;
export 'src/ui/theme/typography.dart' show TypographyRoles;
