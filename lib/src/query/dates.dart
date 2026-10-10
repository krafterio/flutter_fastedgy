/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// Days and the instants that bound them, in the time zone of the device.
//
// A datetime is filtered on a day the way a person means it: « on 8 October »
// is everything from the first to the last instant of that local day, written
// as a range in UTC, and read back as a day when a range covers exactly one.
// The server reads an ISO date only: an instant written without its zone
// would select other rows.

final _day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

String _pad(int value) => value.toString().padLeft(2, '0');

DateTime? _localDay(String? day) {
  final match = _day.firstMatch(day ?? '');

  return match == null
      ? null
      : DateTime(
          int.parse(match[1]!),
          int.parse(match[2]!),
          int.parse(match[3]!),
        );
}

/// The first instant of a local day (`YYYY-MM-DD`), in ISO 8601 and UTC.
String? dayStart(String? day) => _localDay(day)?.toUtc().toIso8601String();

/// The last instant of a local day, in ISO 8601 and UTC.
String? dayEnd(String? day) {
  final start = _localDay(day);

  return start == null
      ? null
      : DateTime(
          start.year,
          start.month,
          start.day,
          23,
          59,
          59,
          999,
        ).toUtc().toIso8601String();
}

/// The local day an instant falls on, `YYYY-MM-DD`; a day passes as is.
String? dayOf(Object? instant) {
  if (instant is! String || instant.isEmpty) {
    return null;
  }

  if (_day.hasMatch(instant)) {
    return instant;
  }

  final date = DateTime.tryParse(instant)?.toLocal();

  return date == null
      ? null
      : '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
}

/// An instant in ISO 8601 and UTC, a day being its first instant in UTC, as
/// a browser reads it.
String? _instant(Object? value) {
  if (value is! String) {
    return null;
  }

  final date = DateTime.tryParse(
    _day.hasMatch(value) ? '${value}T00:00:00Z' : value,
  );

  return date?.toUtc().toIso8601String();
}

/// Whether a range is exactly one local day, from its first to its last
/// instant.
bool coversOneDay(Object? range) {
  if (range is! List || range.length != 2) {
    return false;
  }

  final day = dayOf(range[0]);

  return day != null &&
      dayStart(day) == _instant(range[0]) &&
      dayEnd(day) == _instant(range[1]);
}
