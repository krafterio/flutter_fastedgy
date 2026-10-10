/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// The UI module of flutter_fastedgy: headless widgets and the theme system
/// they draw with.
///
/// Kept out of `flutter_fastedgy.dart` on purpose — an application that only
/// talks to a server never pays for a widget it does not mount.
///
/// Everything theme.dart and rich_text.dart give, with the former names of the
/// animated theme and its tween. It pulls Material in, through the rich text:
/// an application that wants none of it imports theme.dart.
library;

export 'rich_text.dart';
export 'src/ui/theme/legacy_names.dart';
export 'theme.dart';
