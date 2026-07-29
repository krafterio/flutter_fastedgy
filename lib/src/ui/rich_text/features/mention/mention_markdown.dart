/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

import 'mention_address.dart';
import 'mention_span.dart';

/// Writes every mention as the plain link it is stored as: `[#KAS-42](/w/…)`.
///
/// Markdown has no inline objects, and it should not: the field is read by the
/// agent and by whatever else touches it, and a link is something they all
/// understand. The chip is how it is *edited*, not how it is kept.
Document mentionsAsLinks(Document document) =>
    _mapRuns(document, (text, attributes) {
      final mention = Mention.fromJson(attributes[mentionAttribute]);

      if (mention == null) {
        return null;
      }

      return (
        _escaped(mention.label.trim()),
        {AppFlowyRichTextKeys.href: mention.address.uri.toString()},
      );
    });

/// What markdown would read as markup inside a link's text.
///
/// The backslash comes first, or escaping the rest would double back on it.
final _markup = RegExp(r'[\\\[\]@*_`<>~]');

/// A label written so markdown reads it as the words it is.
///
/// A label is what somebody is called, never markup, and the parser helped
/// itself to it: an email in a name — which is what a member with no name is
/// called — was pulled out as a `mailto:` of its own, leaving a chip holding
/// nothing but `@` and the address linked beside it. A bracket closed the link
/// early and took the record with it.
///
/// Escaped rather than stripped, so the name comes back the name it was: the
/// parser eats the backslashes and hands back exactly what was written.
String _escaped(String label) =>
    label.replaceAllMapped(_markup, (match) => '\\${match[0]}');

/// Turns the links that point at a record back into mentions.
///
/// The mirror of [mentionsAsLinks], and the reason a mention survives a round
/// trip at all. A link to anywhere else stays a link.
Document linksAsMentions(Document document) =>
    _mapRuns(document, (text, attributes) {
      final href = attributes[AppFlowyRichTextKeys.href];
      final uri = href is String ? Uri.tryParse(href) : null;
      final address = uri == null ? null : mentionAddressing?.decode(uri);

      if (address == null) {
        return null;
      }

      return (
        mentionPlaceholder,
        {mentionAttribute: Mention(address: address, label: text).toJson()},
      );
    });

/// Rewrites the runs [map] answers for, leaving the rest alone.
///
/// Through JSON: the node tree hands out its attribute maps by reference, and
/// the document being rewritten is the one open in the editor.
Document _mapRuns(
  Document document,
  (String, Map<String, dynamic>)? Function(String text, Map attributes) map,
) {
  final json =
      jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>;

  void walk(Object? node) {
    if (node is! Map) {
      return;
    }

    // A node serialises its attributes under `data`, its delta inside them.
    final delta = node['data'] is Map ? (node['data'] as Map)['delta'] : null;

    if (delta is List) {
      for (final operation in delta) {
        if (operation is! Map ||
            operation['insert'] is! String ||
            operation['attributes'] is! Map) {
          continue;
        }

        final mapped = map(
          operation['insert'] as String,
          operation['attributes'] as Map,
        );

        if (mapped != null) {
          operation['insert'] = mapped.$1;
          operation['attributes'] = mapped.$2;
        }
      }
    }

    final children = node['children'];

    if (children is List) {
      children.forEach(walk);
    }
  }

  walk(json['document']);

  return Document.fromJson(json);
}
