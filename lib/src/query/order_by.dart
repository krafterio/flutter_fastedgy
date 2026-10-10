/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Reads an ordering written as one string, a URL query for instance:
/// `name:asc,created_at:desc` gives `['name:asc', 'created_at:desc']`. A term
/// without its direction is ascending, as the server reads it.
List<String>? parseOrderBy(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return [
    for (final term in value.split(','))
      if (term.trim().isNotEmpty) term.trim(),
  ];
}

/// Writes an ordering as one string, to put it back in a URL.
String? formatOrderBy(List<String>? terms) =>
    terms == null || terms.isEmpty ? null : terms.join(',');

/// The field a term names, and the direction it asks for: `name:desc`, or
/// `name`, ascending.
({String field, String direction}) orderByTerm(String? term) {
  final parts = (term ?? '').split(':');

  return (field: parts.first, direction: parts.length > 1 ? parts[1] : 'asc');
}
