/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../../../theme/component_theme.dart';
import '../../rich_text_theme.dart';

/// How a code block is drawn: its own text, and the colours its scopes wear.
///
/// Its own theme rather than a corner of [RichTextTheme]: a syntax palette is
/// thirty entries an application replaces as a set, and nothing else in the
/// stack reads one.
@immutable
class CodeBlockTheme extends ComponentThemeData {
  final TextStyle text;

  /// highlight.js scope names → the style that scope takes. A scope absent from
  /// the map is drawn as plain [text], which is what makes a partial map valid.
  final Map<String, TextStyle> syntax;

  const CodeBlockTheme({required this.text, required this.syntax});

  /// Muted on purpose: enough contrast to scan code, no rainbow. Built from the
  /// roles alone, so an application that supplies no palette still reads its
  /// code as code.
  factory CodeBlockTheme.from(RichTextTheme theme) {
    final keyword = TextStyle(color: theme.link);
    final literal = TextStyle(color: theme.ink);
    final string = TextStyle(color: theme.mutedText);
    final title = TextStyle(color: theme.ink, fontWeight: FontWeight.w600);
    final name = TextStyle(color: theme.danger);

    return CodeBlockTheme(
      text: theme.codeText,
      syntax: {
        'comment': TextStyle(
          color: theme.mutedText,
          fontStyle: FontStyle.italic,
        ),
        'quote': TextStyle(color: theme.mutedText, fontStyle: FontStyle.italic),
        'keyword': keyword,
        'selector-tag': keyword,
        'doctag': keyword,
        'formula': keyword,
        'literal': literal,
        'number': literal,
        'string': string,
        'regexp': string,
        'addition': string,
        'attribute': string,
        'meta-string': string,
        'title': title,
        'section': title,
        'name': name,
        'tag': name,
        'selector-id': name,
        'deletion': name,
        'meta': TextStyle(color: theme.mutedText),
        'link': TextStyle(
          color: theme.link,
          decoration: TextDecoration.underline,
        ),
        'emphasis': const TextStyle(fontStyle: FontStyle.italic),
        'strong': const TextStyle(fontWeight: FontWeight.w600),
      },
    );
  }

  static CodeBlockTheme of(BuildContext context) {
    return ComponentTheme.maybeOf<CodeBlockTheme>(context) ??
        CodeBlockTheme.from(RichTextTheme.of(context));
  }

  CodeBlockTheme copyWith({TextStyle? text, Map<String, TextStyle>? syntax}) {
    return CodeBlockTheme(
      text: text ?? this.text,
      syntax: syntax ?? this.syntax,
    );
  }
}
