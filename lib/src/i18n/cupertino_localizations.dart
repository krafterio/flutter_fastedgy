/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/widgets.dart';

/// The localizations of the Cupertino widgets (`cupertino_ui`), for an
/// application that draws them, as [materialLocalizationDelegates] are for
/// Material.
const List<LocalizationsDelegate<Object>> cupertinoLocalizationDelegates = [
  GlobalCupertinoLocalizations.delegate,
];
