/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert' show jsonEncode;
import 'dart:math' show max, min;

import 'package:appflowy_editor/appflowy_editor.dart';

/// Brings [editorState]'s document to what [target] holds, touching only the
/// blocks that actually differ.
///
/// Replacing the whole document is the obvious way and the wrong one: every
/// block becomes a new [Node] with a new key, so the editor tears the entire
/// subtree down and builds it again. The text flashes, and each picture — a new
/// widget with no cache behind it — downloads itself over again. A description
/// rewritten by the server on save (a pasted image turned into an attachment)
/// or by the agent goes through this on every arrival.
///
/// A block that did not change is therefore left strictly alone: same node,
/// same key, same element, nothing rebuilt. What did change is updated in place
/// when it is still the same kind of block, and only what has no counterpart is
/// inserted or deleted.
///
/// Answers whether anything was applied.
Future<bool> applyRichTextDiff(
  EditorState editorState,
  Document target, {
  bool isRemote = true,
}) async {
  final transaction = richTextDiff(editorState, target);

  if (transaction == null) {
    return false;
  }

  // A view holds its state read-only and [EditorState.apply] refuses to touch
  // it. This is not an edit though: it is the content itself arriving.
  final editable = editorState.editable;
  editorState.editable = true;

  try {
    await editorState.apply(transaction, isRemote: isRemote);
  } finally {
    editorState.editable = editable;
  }

  _pruneSelection(editorState);

  return true;
}

/// Drops a caret the diff left pointing at nothing: the block it stood in may
/// be gone, or hold less text than it did.
void _pruneSelection(EditorState editorState) {
  final selection = editorState.selection;

  if (selection == null ||
      (_resolves(editorState, selection.start) &&
          _resolves(editorState, selection.end))) {
    return;
  }

  editorState.selection = null;
}

/// A block with no delta — a picture — is selected whole, one offset past it.
bool _resolves(EditorState editorState, Position position) {
  final node = editorState.getNodeAtPath(position.path);

  return node != null && position.offset <= (node.delta?.length ?? 1);
}

/// The smallest transaction taking [editorState]'s document to [target], or
/// null when the two already say the same thing.
///
/// Applied as remote is what the callers want: the content arriving from
/// elsewhere is nobody's keystroke, so it belongs neither in the undo stack nor
/// in the transaction stream an autosave listens to.
Transaction? richTextDiff(EditorState editorState, Document target) {
  final root = editorState.document.root;
  final plan = _Plan(_held(editorState));

  _diffChildren(root, root.children, target.root.children, plan);

  if (plan.isEmpty) {
    return null;
  }

  final transaction = editorState.transaction;

  // Inserts first, deletes second, updates last, each run in document order.
  // Every path below is the one the ORIGINAL document gives; the transaction
  // rebases each operation on the ones already queued (`transformOperation`),
  // which only works if a node is inserted beside its neighbour before that
  // neighbour goes away.
  for (final insert in plan.inserts) {
    transaction.insertNodes(insert.path, insert.nodes);
  }

  for (final node in plan.deletes) {
    transaction.deleteNodesAtPath(node.path);
  }

  for (final update in plan.updates) {
    transaction.updateNode(update.node, update.attributes);
  }

  return transaction;
}

/// Where the caret stands, which the diff has to work around.
///
/// A version arriving while someone is writing is a version that does not know
/// about what they are writing: the two are reconciled by their own next save,
/// never by overwriting the block under their hands. This is not a nicety —
/// a block rewritten under the caret takes the caret's own text with it, and
/// anything watching that text (a mention being written, its trigger sitting in
/// the block) finds nothing where it left it and gives up.
({Path start, Path end})? _held(EditorState editorState) {
  final selection = editorState.selection?.normalized;

  return selection == null
      ? null
      : (start: selection.start.path, end: selection.end.path);
}

class _Plan {
  _Plan(this.held);

  /// Null when nothing is being written, and the whole document is the diff's.
  final ({Path start, Path end})? held;

  final inserts = <({Path path, List<Node> nodes})>[];
  final deletes = <Node>[];
  final updates = <({Node node, Attributes attributes})>[];

  bool get isEmpty => inserts.isEmpty && deletes.isEmpty && updates.isEmpty;

  /// Whether the block at [path] is under the caret, or holds what is.
  ///
  /// An ancestor counts: deleting it would take the block being written with
  /// it. A child does not — it is a block of its own, below the one holding the
  /// caret, and updating it disturbs nothing.
  bool holds(Path path) {
    final held = this.held;

    if (held == null) {
      return false;
    }

    return _leadsTo(path, held.start) ||
        _leadsTo(path, held.end) ||
        (path >= held.start && path <= held.end);
  }

  static bool _leadsTo(Path path, Path caret) =>
      path.length < caret.length && path.equals(caret.sublist(0, path.length));
}

/// Aligns [before] on [after] under [parent] and records what it takes to go
/// from one to the other.
void _diffChildren(
  Node parent,
  List<Node> before,
  List<Node> after,
  _Plan plan,
) {
  final path = parent.path;
  final kept = _longestCommonSubsequence(
    before.map(_signature).toList(),
    after.map(_signature).toList(),
  );

  var from = 0;
  var to = 0;

  for (final (beforeAt, afterAt) in kept) {
    _diffRange(path, before, after, from, beforeAt, to, afterAt, plan);
    from = beforeAt + 1;
    to = afterAt + 1;
  }

  _diffRange(path, before, after, from, before.length, to, after.length, plan);
}

/// What lies between two blocks that stayed: `before[from:end]` has to read as
/// `after[to:last]`.
void _diffRange(
  Path path,
  List<Node> before,
  List<Node> after,
  int from,
  int end,
  int to,
  int last,
  _Plan plan,
) {
  // Same kind of block in the same place: kept and updated rather than swapped,
  // so its widget — and whatever it holds, a downloaded picture included —
  // survives a change of its attributes. Pairing stops at the first mismatch:
  // past it the two sides no longer line up, and pairing on would be guesswork.
  var reused = 0;

  while (reused < min(end - from, last - to) &&
      _pairs(before[from + reused], after[to + reused])) {
    _reuse(before[from + reused], after[to + reused], plan);
    reused++;
  }

  // A block that is being written is neither swapped for another nor deleted,
  // and what would have replaced it is not inserted beside it either — half of
  // an exchange would leave the document saying something neither side does.
  // The whole stretch waits for the caret to move on.
  for (var index = from + reused; index < end; index++) {
    if (plan.holds(before[index].path)) {
      return;
    }
  }

  for (var index = from + reused; index < end; index++) {
    plan.deletes.add(before[index]);
  }

  final added = after.sublist(to + reused, last);

  if (added.isNotEmpty) {
    // Anchored on the block that follows, in the original document: the
    // deletions above have not happened yet.
    plan.inserts.add((path: [...path, end], nodes: added));
  }
}

/// Whether two blocks standing in the same place are the same block, updated,
/// rather than one swapped for another.
///
/// A table never is: what it holds is spread between the block — how many rows
/// and columns it has — and the cells under it, and the two have to agree. A
/// diff that reached into one without the other left a table saying it had nine
/// cells over six, which the editor cannot draw at all: it renders the
/// package's bare `placeholder` in its place, taking the text with it. So a
/// table is replaced whole or left strictly alone — and under the caret it is
/// left alone, as any block being written is.
bool _pairs(Node before, Node after) =>
    before.type == after.type &&
    (before.type != TableBlockKeys.type ||
        _signature(before) == _signature(after));

void _reuse(Node before, Node after, _Plan plan) {
  final attributes = _attributeUpdate(before.attributes, after.attributes);

  // A paragraph carries its text in its attributes, so this is where a block
  // being written would have what arrived composed over it, mid-word.
  if (attributes.isNotEmpty && !plan.holds(before.path)) {
    plan.updates.add((node: before, attributes: attributes));
  }

  _diffChildren(before, before.children, after.children, plan);
}

/// What [before]'s attributes need to read as [after]'s.
///
/// A dropped key is carried as an explicit null: the update is composed onto
/// what is there, so leaving it out would keep the old value instead.
Attributes _attributeUpdate(Attributes before, Attributes after) => {
  for (final key in before.keys)
    if (!after.containsKey(key)) key: null,
  for (final entry in after.entries)
    if (!_same(before[entry.key], entry.value)) entry.key: entry.value,
};

bool _same(Object? a, Object? b) =>
    a == b || jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

/// A block's whole content as one comparable string.
String _signature(Node node) => jsonEncode(
  _canonical(
    node.type == TableBlockKeys.type
        ? _unmeasured(node.toJson())
        : node.toJson(),
  ),
);

/// The heights a table works out for itself as it lays out, and writes back
/// into its own nodes.
///
/// They are not content: a row is as tall as what it holds, markdown carries
/// nothing of it, and a table read back from the server has none — an untouched
/// table would differ from itself on every arrival, to be replaced by the same
/// table without its measurements. A column's width is the other way round: it
/// is dragged, and it is written (see the table feature's markdown).
const _measured = {TableCellBlockKeys.height, TableBlockKeys.colsHeight};

Map<String, dynamic> _unmeasured(Map<String, dynamic> json) => {
  for (final entry in json.entries)
    if (entry.key == 'data' && entry.value is Map)
      entry.key: {
        for (final attribute in (entry.value as Map).entries)
          if (!_measured.contains(attribute.key))
            attribute.key: attribute.value,
      }
    else if (entry.key == 'children' && entry.value is List)
      entry.key: [
        for (final child in entry.value as List)
          if (child is Map<String, dynamic>) _unmeasured(child) else child,
      ]
    else
      entry.key: entry.value,
};

/// The same value with every map key in a fixed order: two blocks built by
/// different paths — one decoded, one typed — carry the same attributes in
/// whatever order they were written, and would otherwise never compare equal.
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();

    return {for (final key in keys) key: _canonical(value[key])};
  }

  if (value is List) {
    return value.map(_canonical).toList();
  }

  return value;
}

/// The blocks common to both sides, in order, as `(beforeIndex, afterIndex)`
/// pairs — everything else is what changed.
List<(int, int)> _longestCommonSubsequence(
  List<String> before,
  List<String> after,
) {
  final rows = before.length;
  final columns = after.length;
  final lengths = List.generate(rows + 1, (_) => List.filled(columns + 1, 0));

  for (var row = rows - 1; row >= 0; row--) {
    for (var column = columns - 1; column >= 0; column--) {
      lengths[row][column] = before[row] == after[column]
          ? lengths[row + 1][column + 1] + 1
          : max(lengths[row + 1][column], lengths[row][column + 1]);
    }
  }

  final common = <(int, int)>[];
  var row = 0;
  var column = 0;

  while (row < rows && column < columns) {
    if (before[row] == after[column]) {
      common.add((row, column));
      row++;
      column++;
    } else if (lengths[row + 1][column] >= lengths[row][column + 1]) {
      row++;
    } else {
      column++;
    }
  }

  return common;
}
