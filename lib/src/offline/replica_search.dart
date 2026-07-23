/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Offline fulltext search over the replica tables, mirroring the server's
/// FulltextField pipeline (`fastedgy/orm/fields/field_fulltext.py`,
/// `fastedgy/orm/filter/search_parser.py`) on SQLite FTS5:
///
/// - the searchable source fields are aggregated into four derived columns
///   on the record (`search_value_fts_a`–`d`, one per search weight) — the
///   SQLite equivalent of the server's per-locale tsvector column;
/// - an external-content FTS5 table indexes those columns (the equivalent of
///   the server's GIN index), kept in sync by AFTER INSERT/UPDATE/DELETE
///   triggers (requires `PRAGMA recursive_triggers = ON`: the internal
///   delete of `INSERT OR REPLACE` must fire the delete trigger);
/// - `unicode61 remove_diacritics 2` reproduces the server's
///   `unaccent` + lowercase folding on both the indexed text and the query;
/// - the Google-style search input is parsed with the server's rules (bare
///   words → optional prefix OR, `+word` mandatory, `-word` excluded,
///   `"quoted phrases"` exact) into FTS5 MATCH expressions;
/// - ranking uses `bm25()` with the per-column weights 1.0/0.4/0.2/0.1 —
///   PostgreSQL's default `ts_rank` weights for A/B/C/D.
///
/// Known deltas with the server: no French stemming (prefix matching
/// compensates for suffix inflections) and `search_fuzzy` degrades to
/// `search` (no pg_trgm equivalent in the bundled SQLite).
library;

import 'local_schema.dart';

const searchWeightLetters = ['a', 'b', 'c', 'd'];

/// bm25 per-column multipliers, in [searchWeightLetters] order.
const searchRankWeights = '1.0, 0.4, 0.2, 0.1';

/// Derived column persisting the aggregated source text of a weight class.
String searchColumn(String weight) => 'search_value_fts_$weight';

List<String> get searchColumns =>
    searchWeightLetters.map(searchColumn).toList();

/// Name of the FTS5 index table of a replica [table].
String ftsTableName(String table) => '${table}_fts';

/// DDL of the FTS5 index of [table] — external content: the index reads the
/// derived columns of the replica table (no text duplication) and rebuilds
/// from them with the `rebuild` command.
String ftsCreateSql(String table) {
  return 'CREATE VIRTUAL TABLE "${ftsTableName(table)}" USING fts5('
      '${searchColumns.join(', ')}, '
      "content='$table', tokenize='unicode61 remove_diacritics 2')";
}

/// DDL of the triggers keeping the FTS5 index of [table] in sync, keyed by
/// trigger name. Stored verbatim in `sqlite_master.sql`, so the store diffs
/// them by strict equality to detect any stale layout.
Map<String, String> ftsTriggerSqls(String table) {
  final fts = ftsTableName(table);
  final columns = searchColumns.map((column) => '"$column"').join(', ');
  final newValues = searchColumns.map((column) => 'new."$column"').join(', ');
  final oldValues = searchColumns.map((column) => 'old."$column"').join(', ');
  final insert =
      'INSERT INTO "$fts"(rowid, $columns) VALUES (new.rowid, $newValues);';
  final delete =
      'INSERT INTO "$fts"("$fts", rowid, $columns) '
      "VALUES ('delete', old.rowid, $oldValues);";

  return {
    '${fts}_ai':
        'CREATE TRIGGER "${fts}_ai" AFTER INSERT ON "$table" BEGIN $insert END',
    '${fts}_ad':
        'CREATE TRIGGER "${fts}_ad" AFTER DELETE ON "$table" BEGIN $delete END',
    '${fts}_au':
        'CREATE TRIGGER "${fts}_au" AFTER UPDATE ON "$table" '
        'BEGIN $delete $insert END',
  };
}

/// Correlated bm25 rank of [rootAlias] for a MATCH placeholder — the offline
/// equivalent of the server's `ts_rank` extra select (lower bm25 = more
/// relevant, the sign is inverted versus `ts_rank`).
String ftsRankSql(String table, String rootAlias) {
  final fts = '"${ftsTableName(table)}"';

  return '(SELECT bm25($fts, $searchRankWeights) FROM $fts '
      'WHERE $fts MATCH ? AND rowid = $rootAlias.rowid)';
}

/// `unaccent` folds ligatures while `remove_diacritics` does not (they are
/// not diacritics) — normalize them on both the indexed text and the query.
String normalizeSearchText(String value) => value
    .replaceAll('œ', 'oe')
    .replaceAll('Œ', 'OE')
    .replaceAll('æ', 'ae')
    .replaceAll('Æ', 'AE');

/// Values of the derived search columns of [record], grouped by weight —
/// the mirror of the server's tsvector recompute (`str(value)` per source
/// field). Localized map payloads are skipped: the server resolves them with
/// the request locale, which the replica does not persist.
Map<String, String> computeSearchValues(
  LocalModelSchema model,
  Map<String, dynamic> record,
) {
  final buffers = {
    for (final weight in searchWeightLetters) weight: StringBuffer(),
  };

  model.searchWeights.forEach((field, weight) {
    final value = record[field];

    if (value == null || value is Map || value is List) {
      return;
    }

    final text = normalizeSearchText('$value');

    if (text.isEmpty) {
      return;
    }

    final buffer = buffers[weight]!;

    if (buffer.isNotEmpty) {
      buffer.write(' ');
    }

    buffer.write(text);
  });

  return {
    for (final weight in searchWeightLetters)
      searchColumn(weight): buffers[weight]!.toString(),
  };
}

/// A search input compiled to FTS5 MATCH expressions: [positive] selects the
/// matching rowids, [excluded] removes the rowids matching a `-term`. Both
/// null when the input holds no usable term.
class FtsSearchQuery {
  final String? positive;
  final String? excluded;

  const FtsSearchQuery({this.positive, this.excluded});

  bool get isEmpty => positive == null && excluded == null;
}

final _quoteChars = RegExp('["«»‘’‚‛“”„‟‹›「」『』＂]');
final _alnum = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
final _anyAlnum = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Parse a Google-style search input into FTS5 MATCH expressions, with the
/// server's rules (`parse_search_input`): bare words are optional prefix
/// matches OR'ed together, `+word` is mandatory, `-word` is excluded and
/// `"quoted phrases"` match exactly (no prefix). Terms are individually
/// quoted so FTS5 keywords (AND/OR/NOT/NEAR) stay plain text.
FtsSearchQuery parseFtsSearch(String raw) {
  final normalized = _normalizeInput(raw.trim());
  final optional = <String>[];
  final mandatory = <String>[];
  final excluded = <String>[];

  var i = 0;

  while (i < normalized.length) {
    final char = normalized[i];

    if (char == ' ') {
      i++;
      continue;
    }

    if (char == '"') {
      var end = normalized.indexOf('"', i + 1);

      if (end == -1) {
        end = normalized.length;
      }

      final content = i + 1 < normalized.length
          ? normalized.substring(i + 1, end)
          : '';
      final words = content
          .split(' ')
          .where((word) => word.contains(_anyAlnum))
          .toList();

      if (words.isNotEmpty) {
        mandatory.add('"${words.join(' ')}"');
      }

      i = end + 1;
      continue;
    }

    if (char == '+' || char == '-') {
      var j = i + 1;

      while (j < normalized.length && normalized[j] == ' ') {
        j++;
      }

      if (j < normalized.length && _alnum.hasMatch(normalized[j])) {
        final (word, next) = _readWord(normalized, j);
        i = next;

        if (word.isNotEmpty) {
          (char == '+' ? mandatory : excluded).add('"$word" *');
        }

        continue;
      }

      i++;
      continue;
    }

    if (!_alnum.hasMatch(char)) {
      i++;
      continue;
    }

    final (word, next) = _readWord(normalized, i);
    i = next;

    if (word.isNotEmpty) {
      optional.add('"$word" *');
    }
  }

  final positive = <String>[
    if (optional.length > 1) '(${optional.join(' OR ')})',
    if (optional.length == 1) optional.single,
    ...mandatory,
  ];

  return FtsSearchQuery(
    positive: positive.isEmpty ? null : positive.join(' AND '),
    excluded: excluded.isEmpty ? null : excluded.join(' OR '),
  );
}

/// Normalize the raw input: unify Unicode quotes, fold ligatures, keep only
/// letters/digits/space/quote/`+`/`-`/apostrophe (the rest becomes a space).
String _normalizeInput(String raw) {
  final unified = normalizeSearchText(raw).replaceAll(_quoteChars, '"');
  final buffer = StringBuffer();

  for (final char in unified.split('')) {
    if (_alnum.hasMatch(char) ||
        char == ' ' ||
        char == '"' ||
        char == '+' ||
        char == '-' ||
        char == "'") {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }

  return buffer.toString();
}

/// Read a word (letters/digits plus inner apostrophes/hyphens) from [start],
/// returning it stripped of surrounding `'`/`-` with the next position.
(String, int) _readWord(String raw, int start) {
  var end = start;

  while (end < raw.length &&
      (_alnum.hasMatch(raw[end]) || raw[end] == "'" || raw[end] == '-')) {
    end++;
  }

  var word = raw.substring(start, end);
  word = word
      .replaceAll(RegExp(r"^['-]+"), '')
      .replaceAll(RegExp(r"['-]+$"), '');

  return (word, end);
}
