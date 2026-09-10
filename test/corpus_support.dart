/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/ui.dart';

/// The shared markdown corpus: what the stored format says, written down.
///
/// `fixtures_generator_test.dart` writes it and `corpus_test.dart` holds this
/// package to it. The same files are copied into every other implementation of
/// the format, where the very same assertions are run on them. A fixture is
/// therefore never a snapshot of one implementation.
const String corpusDirectory = 'test/fixtures/markdown';

/// Written with the feature set an application actually mounts, `++text++`
/// included: what the corpus describes has to be what is really stored.
final MarkdownRichTextCodec corpusCodec = MarkdownRichTextCodec(
  features: defaultRichTextFeatures.and([const PlusUnderlineFeature()]),
);

/// Where a mention points, in the shape melimelo routes.
///
/// The corpus describes mentions, and a mention is only a mention where an
/// application says which paths are its own: without this, `[x](/notes/12)` is
/// a link on both sides and the fixtures would describe nothing.
class _CorpusAddressing extends MentionAddressing {
  const _CorpusAddressing();

  static const Map<String, String> _paths = {
    'note': '/notes',
    'user': '/household/members',
  };

  @override
  Uri? encode({required String model, required int id}) {
    final path = _paths[model];

    return path == null ? null : Uri.parse('$path/$id');
  }

  @override
  MentionAddress? decode(Uri uri) {
    if (uri.hasScheme) {
      return null;
    }

    final id = int.tryParse(
      uri.pathSegments.isEmpty ? '' : uri.pathSegments.last,
    );

    if (id == null) {
      return null;
    }

    for (final entry in _paths.entries) {
      if (uri.path == '${entry.value}/$id') {
        return MentionAddress(model: entry.key, id: id, uri: uri);
      }
    }

    return null;
  }
}

/// Registers what the corpus needs before a fixture is read or written.
void useCorpusServices() {
  if (!hasService<MentionAddressing>()) {
    container.registerSingleton<MentionAddressing>(const _CorpusAddressing());
  }
}

/// The block vocabulary the corpus is written in, which is no implementation's
/// own: a fixture that took a side would stop being an arbiter.
const Map<String, String> neutralTypes = {
  'paragraph': 'paragraph',
  'heading': 'heading',
  'bulleted_list': 'bullet',
  'numbered_list': 'numbered',
  'todo_list': 'todo',
  'quote': 'quote',
  'divider': 'divider',
  'code': 'code',
  'image': 'image',
  'table': 'table',
};

/// Written out in this order on both sides, so two outlines compare literally.
const List<String> markOrder = [
  'bold',
  'italic',
  'underline',
  'strikethrough',
  'code',
];

/// The first [items] entry [matches] answers for, or null.
///
/// Written out rather than pulled from `package:collection`: a corpus helper is
/// not worth a dependency the package would then ship.
T? _firstWhere<T>(Iterable<T> items, bool Function(T) matches) {
  for (final item in items) {
    if (matches(item)) {
      return item;
    }
  }

  return null;
}

/// The width of each column, as the first row of a table carries them.
List<int> _widthsOf(Node table) {
  final columns = table.attributes[TableBlockKeys.colsLen] as int? ?? 0;

  return [
    for (var column = 0; column < columns; column++)
      ((_firstWhere(
                    table.children,
                    (cell) =>
                        cell.attributes[TableCellBlockKeys.colPosition] ==
                            column &&
                        cell.attributes[TableCellBlockKeys.rowPosition] == 0,
                  )?.attributes[TableCellBlockKeys.width]
                  as num?) ??
              TableDefaults.colWidth)
          .round(),
  ];
}

/// What a block says, a mention read as the label it draws rather than as the
/// placeholder it is stored as.
String _saidBy(Node? node) {
  final buffer = StringBuffer();

  for (final operation in node?.delta ?? Delta()) {
    if (operation is! TextInsert) {
      continue;
    }

    buffer.write(
      Mention.fromJson(operation.attributes?[mentionAttribute])?.label ??
          operation.text,
    );
  }

  return buffer.toString();
}

/// What each cell of a table says, row by row, and how wide its columns are.
List<Object?> _cellsOf(Node table) {
  final columns = table.attributes[TableBlockKeys.colsLen] as int? ?? 0;
  final rows = table.attributes[TableBlockKeys.rowsLen] as int? ?? 0;

  Node? cellAt(int column, int row) => _firstWhere(
    table.children,
    (cell) =>
        cell.attributes[TableCellBlockKeys.colPosition] == column &&
        cell.attributes[TableCellBlockKeys.rowPosition] == row,
  );

  return [
    for (var row = 0; row < rows; row++)
      [
        for (var column = 0; column < columns; column++)
          _saidBy(
            _firstWhere(cellAt(column, row)?.children ?? const [], (_) => true),
          ),
      ],
  ];
}

/// A document as the corpus describes it: what each block is, how deep it sits,
/// what it says, and how what it says is marked.
List<Map<String, Object?>> outlineOf(Document document) {
  final blocks = <Map<String, Object?>>[];

  void walk(Node node, int indent) {
    final runs = <Map<String, Object?>>[];

    for (final operation in node.delta ?? Delta()) {
      if (operation is! TextInsert) {
        continue;
      }

      final attributes = operation.attributes ?? const {};

      final mention = Mention.fromJson(attributes[mentionAttribute]);

      runs.add({
        // A mention is drawn from its label, and stored as a placeholder no
        // outline should describe.
        't': mention?.label ?? operation.text,
        'm': [
          for (final key in markOrder)
            if (attributes[key] == true)
              key == 'strikethrough' ? 'strike' : key,
        ],
        'href': attributes[AppFlowyRichTextKeys.href],
        if (mention != null)
          'mention': {'model': mention.address.model, 'id': mention.address.id},
      });
    }

    final isTable = node.type == TableBlockKeys.type;

    blocks.add({
      'type': neutralTypes[node.type] ?? node.type,
      'indent': indent,
      if (isTable) 'cells': _cellsOf(node),
      'attrs': {
        if (node.attributes[HeadingBlockKeys.level] != null)
          'level': node.attributes[HeadingBlockKeys.level],
        if (node.attributes[TodoListBlockKeys.checked] != null)
          'checked': node.attributes[TodoListBlockKeys.checked],
        if (node.attributes[CodeBlockKeys.language] != null)
          'language': node.attributes[CodeBlockKeys.language],
        if (node.type == ImageBlockKeys.type)
          'src': node.attributes[ImageBlockKeys.url],
        if (node.attributes[ImageBlockKeys.width] != null)
          'width': (node.attributes[ImageBlockKeys.width] as num).round(),
        if (node.attributes[ImageBlockKeys.height] != null)
          'height': (node.attributes[ImageBlockKeys.height] as num).round(),
        if (isTable) 'widths': _widthsOf(node),
      },
      'runs': runs,
    });

    // A table is its cells, not a parent holding them: the encoder never walks
    // into one, and an outline that did would describe a document no other
    // implementation holds.
    if (isTable) {
      return;
    }

    for (final child in node.children) {
      walk(child, indent + 1);
    }
  }

  for (final node in document.root.children) {
    walk(node, 0);
  }

  return blocks;
}
