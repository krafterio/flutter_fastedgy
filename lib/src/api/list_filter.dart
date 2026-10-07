/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

/// Query Builder rules ANDed, as a list keeps them in its URL.
class ListFilter {
  final List<List<dynamic>> rules;

  const ListFilter([this.rules = const []]);

  static const ListFilter empty = ListFilter();

  bool get isEmpty => rules.isEmpty;
  bool get isNotEmpty => rules.isNotEmpty;

  Set<String> get fields => {for (final rule in rules) ?fieldOf(rule)};

  List<List<dynamic>> on(String field) => [
    for (final rule in rules)
      if (fieldOf(rule) == field) rule,
  ];

  ListFilter withField(String field, List<List<dynamic>> replacement) =>
      ListFilter([
        for (final rule in rules)
          if (fieldOf(rule) != field) rule,
        ...replacement,
      ]);

  String encode() => isEmpty ? '' : jsonEncode(rules);

  /// Never throws: a URL is user input, and a rule [allow] refuses is dropped.
  static ListFilter decode(String? raw, {bool Function(String field)? allow}) {
    if (raw == null || raw.trim().isEmpty) {
      return empty;
    }

    final Object? data;

    try {
      data = jsonDecode(raw);
    } on FormatException {
      return empty;
    }

    if (data is! List) {
      return empty;
    }

    final rules = <List<dynamic>>[];

    for (final rule in data) {
      final field = rule is List ? fieldOf(rule) : null;

      if (field != null && (allow == null || allow(field))) {
        rules.add(rule as List<dynamic>);
      }
    }

    return ListFilter(rules);
  }

  static String? fieldOf(List<dynamic> rule) {
    if (rule.length < 2) {
      return null;
    }

    final head = rule.first;
    final second = rule[1];

    if (head == '&' || head == '|') {
      if (second is! List) {
        return null;
      }

      final fields = {
        for (final inner in second) inner is List ? fieldOf(inner) : null,
      };

      return fields.length == 1 ? fields.single : null;
    }

    return head is String && head.isNotEmpty && second is String ? head : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ListFilter && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => 'ListFilter(${encode()})';
}
