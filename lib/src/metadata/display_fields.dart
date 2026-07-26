/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'models.dart';

/// Columns a record is displayed by, most specific first.
///
/// FastEdgy metadata carries no display-field notion — `__str__` is server-side
/// only — so naming a record is a client convention. Kept in one place so a
/// relation picker, a group header and a chip all name it the same way.
const List<String> labelFieldCandidates = [
  'display_name',
  'name',
  'label',
  'title',
  'reference',
  'email',
  'code',
];

/// The field [model] is best displayed by, `id` when it has none of the
/// conventional ones (a record shown as `#42` beats a blank).
String resolveLabelField(MetadataModel model) {
  for (final candidate in labelFieldCandidates) {
    if (model.fields.containsKey(candidate)) {
      return candidate;
    }
  }

  return 'id';
}

/// Columns holding a record's picture, most specific first. Same convention as
/// [labelFieldCandidates]: the metadata says a field is a `char`, not that it
/// holds an image path.
const List<String> imageFieldCandidates = [
  'avatar',
  'image',
  'image_url',
  'photo',
  'logo',
];

/// The field holding [model]'s picture, or null when it has none — a record
/// that shows as initials rather than a picture.
String? resolveImageField(MetadataModel model) {
  for (final candidate in imageFieldCandidates) {
    if (model.fields[candidate]?.type == 'char') {
      return candidate;
    }
  }

  return null;
}
