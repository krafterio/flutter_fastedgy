/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

/// The localizations of the Material widgets (`material_ui`), for an
/// application that draws them: since Flutter 3.47 they are distinct types
/// from those `flutter_localizations` gives the Material still inside
/// `package:flutter`, and a locale other than English finds none of them
/// without these.
const List<LocalizationsDelegate<Object>> materialLocalizationDelegates = [
  GlobalMaterialLocalizations.delegate,
];
