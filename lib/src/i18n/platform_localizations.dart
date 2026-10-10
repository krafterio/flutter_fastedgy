/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import 'cupertino_localizations.dart';
import 'i18n.dart';
import 'material_localizations.dart';

extension FastEdgyLocalizations on BuildContext {
  /// The delegates an application's App widget must be given.
  ///
  /// `context.localizationDelegates` alone is not enough: it carries the
  /// globals of `flutter_localizations`, which localize the Material and
  /// Cupertino still shipped inside `package:flutter`. Since Flutter 3.47 the
  /// widgets actually rendered come from `material_ui` and `cupertino_ui`,
  /// whose localizations are distinct types, and a locale other than English
  /// finds none of them.
  List<LocalizationsDelegate> get fastEdgyLocalizationDelegates => [
    ...localizationDelegates,
    ...materialLocalizationDelegates,
    ...cupertinoLocalizationDelegates,
    activeLocaleDelegate,
  ];
}
