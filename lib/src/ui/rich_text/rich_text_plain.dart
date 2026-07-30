/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Markdown reduced to the words it says.
///
/// For everywhere rich text cannot be drawn and a line of plain text is all
/// there is room for: a notification's body, the last message under a
/// conversation's name, an event two lines tall on a planner.
///
/// A scan over the string, never a document decoded and walked. This runs in
/// the build of a list item — a parse per frame is not something a preview can
/// pay for — and it has to survive text no editor of ours wrote: a description
/// synchronised from an external calendar arrives as HTML.
///
/// [singleLine] puts everything on one line, which is what a preview and a
/// notification both want. Off, the blocks stay on lines of their own.
String markdownToPlainText(String? markdown, {bool singleLine = true}) {
  if (markdown == null || markdown.isEmpty) {
    return '';
  }

  var text = markdown;

  text = text.replaceAll(_hiddenElement, ' ');
  text = text.replaceAll(_fence, '');
  text = text.replaceAll(_image, '');
  text = text.replaceAllMapped(_link, (match) => match[1] ?? '');
  text = text.replaceAllMapped(_autolink, (match) => match[1] ?? '');
  text = text.replaceAll(_separatingTag, ' ');
  text = text.replaceAll(_tag, '');
  text = text.replaceAllMapped(_entity, _decodeEntity);
  text = text.replaceAllMapped(_escaped, _mask);
  text = text.replaceAll(_tableRule, '');
  text = text.replaceAll(_cell, ' ');
  text = text.replaceAll(_horizontalRule, '');
  text = text.replaceAll(_blockMarker, '');
  text = text.replaceAllMapped(_strongMark, (match) => match[2] ?? '');
  text = text.replaceAllMapped(_starMark, (match) => match[1] ?? '');
  text = text.replaceAllMapped(_underscoreMark, (match) => match[1] ?? '');
  text = text.replaceAllMapped(_strikeMark, (match) => match[1] ?? '');
  text = text.replaceAllMapped(_underlineMark, (match) => match[1] ?? '');
  text = text.replaceAllMapped(_codeMark, (match) => match[1] ?? '');
  text = text.replaceAllMapped(_masked, _unmask);

  if (singleLine) {
    return text.replaceAll(_anyBlank, ' ').trim();
  }

  return text
      .replaceAll(_trailingBlanks, '')
      .replaceAll(_blankLines, '\n\n')
      .trim();
}

/// Taken out with what they hold: a stylesheet reads as a wall of text, and a
/// mail pasted whole into a description brings one.
final _hiddenElement = RegExp(
  r'<(style|script|head)\b[^>]*>.*?</\1\s*>',
  dotAll: true,
  caseSensitive: false,
);

/// The rails of a fenced block, never what stands between them: the code is
/// what the block says.
final _fence = RegExp(r'^[ \t]*(?:```|~~~).*$', multiLine: true);

final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');

final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');

/// A link written as itself, and the address is the words: a mention travels
/// as a link, so this is also where `@Name` comes back.
final _autolink = RegExp(
  r'<((?:https?|mailto|tel|sip|callto|ftp):[^>\s]+|[^<>\s@]+@[^<>\s]+)>',
  caseSensitive: false,
);

/// Tags that stood between two words rather than around them.
final _separatingTag = RegExp(
  r'<br\s*/?>|</(?:p|div|li|tr|td|th|h[1-6]|blockquote)\s*>',
  caseSensitive: false,
);

final _tag = RegExp(r'</?[a-zA-Z][^>]*>');

final _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,10});');

/// The row of dashes under a table's headings, which says nothing.
final _tableRule = RegExp(
  r'^[ \t]*\|?[ \t:|-]*-[ \t:|-]*\|[ \t:|-]*$',
  multiLine: true,
);

final _cell = RegExp(r'[ \t]*\|[ \t]*');

final _horizontalRule = RegExp(
  r'^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$',
  multiLine: true,
);

/// What a line opens with to say which block it is.
final _blockMarker = RegExp(
  r'^[ \t]*(?:>[ \t]?|#{1,6}[ \t]+|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|[0-9]+[.)][ \t]+)',
  multiLine: true,
);

final _strongMark = RegExp(r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1', dotAll: true);

final _starMark = RegExp(r'\*(?=\S)([^*\n]+?)(?<=\S)\*');

/// Only around whole words: an identifier written `snake_case` is a word, not
/// something in italics.
final _underscoreMark = RegExp(
  r'(?<![\p{L}\p{N}_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\p{L}\p{N}_])',
  unicode: true,
);

final _strikeMark = RegExp(r'~~(?=\S)(.+?)(?<=\S)~~', dotAll: true);

final _underlineMark = RegExp(r'\+\+(?=\S)([^\n]+?)(?<=\S)\+\+');

final _codeMark = RegExp(r'`+([^`]*)`+');

final _escaped = RegExp(r'\\([\\`*_{}\[\]()#+\-.!>~|])');

final _masked = RegExp('\u0000([0-9]+);');

/// A character somebody escaped is put out of reach of the passes below and
/// brought back once they have run: `\*` is a star, and a star the marks are
/// stripped from is the one that was written to be kept.
///
/// Behind a NUL, which nothing anybody typed holds: a marker made of printable
/// characters would be one more thing needing an escape of its own.
String _mask(Match match) => '\u0000${match[1]!.codeUnitAt(0)};';

String _unmask(Match match) => String.fromCharCode(int.parse(match[1]!));

final _anyBlank = RegExp(r'\s+');

final _trailingBlanks = RegExp(r'[ \t]+$', multiLine: true);

final _blankLines = RegExp(r'\n{3,}');

const _entities = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'bull': '•',
  'middot': '·',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'laquo': '«',
  'raquo': '»',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'euro': '€',
  'copy': '©',
  'reg': '®',
  'deg': '°',
  'sol': '/',
  'eacute': 'é',
  'egrave': 'è',
  'ecirc': 'ê',
  'euml': 'ë',
  'agrave': 'à',
  'acirc': 'â',
  'ccedil': 'ç',
  'icirc': 'î',
  'iuml': 'ï',
  'ocirc': 'ô',
  'oelig': 'œ',
  'ugrave': 'ù',
  'ucirc': 'û',
  'uuml': 'ü',
  'uml': '¨',
};

/// An entity nobody taught it is left standing: `&eacute;` dropped from a word
/// mangles the word, and shown as it is at least reads.
String _decodeEntity(Match match) {
  final name = match[1]!;

  if (!name.startsWith('#')) {
    final known = _entities[name];

    if (known != null) {
      return known;
    }

    // `&Eacute;` is the capital of `&eacute;`: entity names carry their case.
    final lowercase = _entities[name.toLowerCase()];

    return lowercase == null ? match[0]! : lowercase.toUpperCase();
  }

  final hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
  final code = int.tryParse(
    hex ? name.substring(2) : name.substring(1),
    radix: hex ? 16 : 10,
  );

  if (code == null || code < 0x20 || code > 0x10FFFF) {
    return match[0]!;
  }

  return String.fromCharCode(code);
}
