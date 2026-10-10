/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../i18n/i18n.dart';

/// A text of the query builder in the language of the application, the
/// English text being the key, its `{name}`s filled in from [named].
String say(String key, [Map<String, Object?>? named]) =>
    t(key, named?.map((name, value) => MapEntry(name, '$value')));

/// One of two texts by a count, `{count}` filled in: `1 filter`, `3 filters`.
String sayCount(int count, String one, String many) =>
    say(count == 1 ? one : many, {'count': count});
