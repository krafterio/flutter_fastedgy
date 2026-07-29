/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';

/// How far one level of nesting is written in.
///
/// Four spaces, which is what markdown itself indents with, and which nothing
/// of ours can be mistaken for: a code block is always written fenced, so an
/// indented line never means code here — it means a block belonging to the one
/// above it.
const _step = 4;

/// Blocks whose children belong to the block rather than hanging under it.
///
/// A table's cells are the table: markdown writes them as its rows, so they are
/// never a chunk of their own and never indented under it.
const _wholeBlocks = {TableBlockKeys.type};

/// Writes a document one block per chunk, each child indented under its parent.
///
/// Markdown only nests inside a list item, and the package we decode with
/// flattens even that unless the child is another list item — a paragraph
/// indented under anything comes back glued into its parent's own text, newline
/// and all. Nesting is therefore ours to write and ours to read: [encodeBlock]
/// is only ever handed one block, stripped of its children, and this places it.
String encodeNestedMarkdown(
  Document document,
  String Function(Node block) encodeBlock,
) {
  final chunks = <String>[];

  void walk(Node node, int depth) {
    // A whole block is handed over with its children, and nothing walks into
    // them: they are the block, not content nested under it. Stripped of its
    // cells a table has nothing left to write, and the package's encoder threw
    // on the first cell it went looking for — which the autosave ran into.
    final whole = _wholeBlocks.contains(node.type);
    final markdown = encodeBlock(
      whole ? node.copyWith() : node.copyWith(children: const []),
    ).trim();

    if (markdown.isNotEmpty) {
      chunks.add(_indented(markdown, depth));
    }

    if (whole) {
      return;
    }

    for (final child in node.children) {
      walk(child, depth + 1);
    }
  }

  for (final node in document.root.children) {
    walk(node, 0);
  }

  return chunks.join('\n\n');
}

/// Reads back what [encodeNestedMarkdown] wrote, [decodeBlock] handling one
/// block at a time with nothing indented left in it.
///
/// A level deeper than the one before it belongs to it; a level with nothing
/// above to belong to stands on its own rather than being dropped.
List<Node> decodeNestedMarkdown(
  String source,
  List<Node> Function(String markdown) decodeBlock,
) {
  final roots = <Node>[];
  final open = <int, Node>{};

  for (final (depth, markdown) in _chunksOf(source)) {
    for (final node in decodeBlock(markdown)) {
      final parent = _parentOf(open, depth);

      if (parent == null) {
        roots.add(node);
      } else {
        parent.insert(node);
      }

      open.removeWhere((at, _) => at >= depth);
      open[depth] = node;
    }
  }

  return roots;
}

/// The nearest block above [depth] that something at [depth] hangs off.
Node? _parentOf(Map<int, Node> open, int depth) {
  for (var at = depth - 1; at >= 0; at--) {
    if (open[at] case final parent?) {
      return parent;
    }
  }

  return null;
}

String _indented(String markdown, int depth) {
  if (depth == 0) {
    return markdown;
  }

  final padding = ' ' * (_step * depth);

  return markdown
      .split('\n')
      .map((line) => line.isEmpty ? line : '$padding$line')
      .join('\n');
}

/// Splits [source] into the blocks it holds, each with the depth it was written
/// at and its own indentation taken back off.
///
/// A blank line ends a block, and so does a change of depth. A fence is the
/// exception: everything up to its closing line belongs to it whatever it looks
/// like, or a blank line inside a code sample would cut it in two.
Iterable<(int, String)> _chunksOf(String source) {
  final chunks = <(int, String)>[];
  var lines = <String>[];
  var depth = 0;
  var fenced = false;

  void flush() {
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }

    if (lines.isNotEmpty) {
      chunks.add((depth, lines.join('\n')));
    }

    lines = [];
  }

  for (final line in source.split('\n')) {
    if (fenced) {
      final body = _dedented(line, depth);
      lines.add(body);
      fenced = !body.trimLeft().startsWith('```');

      continue;
    }

    if (line.trim().isEmpty) {
      flush();

      continue;
    }

    final at = _depthOf(line);

    if (lines.isEmpty) {
      depth = at;
    } else if (at != depth) {
      flush();
      depth = at;
    }

    final body = _dedented(line, depth);
    lines.add(body);
    fenced = body.trimLeft().startsWith('```');
  }

  flush();

  return chunks;
}

/// How deep [line] is written in.
///
/// A tab counts for a level of its own: it is what the package used to write
/// nesting with, so a document stored before this reads back as the tree it was
/// rather than as one paragraph holding its children's text.
int _depthOf(String line) {
  var depth = 0;
  var index = 0;

  while (index < line.length) {
    if (line[index] == '\t') {
      depth++;
      index++;
    } else if (line.startsWith(' ' * _step, index)) {
      depth++;
      index += _step;
    } else {
      break;
    }
  }

  return depth;
}

String _dedented(String line, int depth) {
  var index = 0;

  for (var level = 0; level < depth && index < line.length; level++) {
    if (line[index] == '\t') {
      index++;
    } else if (line.startsWith(' ' * _step, index)) {
      index += _step;
    } else {
      break;
    }
  }

  return line.substring(index);
}
