/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show getLogger;

import 'mention_address.dart';
import 'mention_options.dart';
import 'mention_source.dart';
import 'mention_span.dart';

final _log = getLogger('rich_text_mention');

/// How long a keystroke waits before the trigger asks its source again.
const _debounce = Duration(milliseconds: 180);

/// What a query may grow to before the trigger is taken to have been ordinary
/// punctuation after all. Spaces are allowed inside it — a project is called
/// "Refonte du site" — so something has to end the hunt.
const _maxQuery = 60;

/// What may sit right before a trigger for it to arm.
///
/// A word boundary, exactly as GitHub and Odoo have it: an address holding
/// `a@b.com`, or a price written `100%`, must stay what it is.
bool _isBoundary(String character) =>
    character.trim().isEmpty || '([{<"\'‘“'.contains(character);

/// The typing machine behind the mentions of one editor: what is armed, what
/// has been typed since, and what the source answers.
///
/// It owns no widget — [MentionFeature] hands it the keystrokes and the menu
/// reads it — and it holds nothing of the editor beyond the position it is
/// watching, so a document rebuilt under it simply closes it.
class MentionController extends ChangeNotifier {
  MentionController(this.sources, {this.options = MentionOptions.none});

  final MentionSources sources;

  /// What the document says to its sources. Reassigned rather than fixed: the
  /// controller outlives a rebuild, and a document may be handed new options
  /// while the same editor state stays in place.
  MentionOptions options;

  EditorState? _editorState;
  MentionSource? _source;
  Path? _path;
  int _triggerStart = 0;

  String _query = '';
  List<MentionCandidate> _candidates = const [];
  int _highlighted = 0;
  bool _searching = false;

  Timer? _timer;
  int _search = 0;
  StreamSubscription<EditorTransactionValue>? _edits;
  VoidCallback? _onSelection;

  /// Where the caret stood when the trigger was typed, in global coordinates.
  /// Captured once: a menu that walked along with the caret as the query grew
  /// would be unreadable.
  Rect? anchor;

  bool get isOpen => _source != null;

  MentionSource? get source => _source;

  String get query => _query;

  List<MentionCandidate> get candidates => _candidates;

  int get highlighted => _highlighted;

  bool get isSearching => _searching;

  /// The source [character] arms, given the [before] text it was typed after,
  /// or null when it is just a character.
  ///
  /// Tried in the registry's arming order — longest trigger first, so `::` wins
  /// over a `:` that would also match.
  MentionSource? sourceFor(String character, String before) {
    final typed = before + character;

    for (final source in sources.armingOrder) {
      if (!typed.endsWith(source.trigger)) {
        continue;
      }

      final start = typed.length - source.trigger.length;

      if (start == 0 || _isBoundary(typed[start - 1])) {
        return source;
      }
    }

    return null;
  }

  /// Arms [source] on the trigger that ends at [caret] in the node at [path].
  void open(
    EditorState editorState,
    MentionSource source,
    Path path,
    int caret,
  ) {
    close();

    _editorState = editorState;
    _source = source;
    _path = path;
    _triggerStart = caret - source.trigger.length;
    _query = '';
    _candidates = const [];
    _highlighted = 0;

    // A transaction moves the text under the trigger; the selection moves
    // without one every time an arrow key is pressed. Both can end the hunt.
    _edits = editorState.transactionStream.listen((_) => sync(), onDone: close);
    _onSelection = sync;
    editorState.selectionNotifier.addListener(_onSelection!);

    notifyListeners();
    unawaited(_ask());
  }

  /// Re-reads the document under the trigger and closes when it no longer says
  /// what it did — the trigger deleted, the caret gone elsewhere, the query run
  /// past what a name can be.
  void sync() {
    final editorState = _editorState;
    final source = _source;
    final path = _path;

    if (editorState == null || source == null || path == null) {
      return;
    }

    final selection = editorState.selection;
    final delta = editorState.getNodeAtPath(path)?.delta;

    if (selection == null ||
        !selection.isCollapsed ||
        !selection.end.path.equals(path) ||
        delta == null) {
      return close();
    }

    final text = delta.toPlainText();
    final start = _triggerStart + source.trigger.length;
    final caret = selection.end.offset;

    if (caret < start ||
        text.length < start ||
        text.substring(_triggerStart, start) != source.trigger) {
      return close();
    }

    final query = text.substring(start, caret.clamp(start, text.length));

    if (query.length > _maxQuery) {
      return close();
    }

    if (query != _query) {
      _query = query;
      _highlighted = 0;
      notifyListeners();
      unawaited(_ask());
    }
  }

  Future<void> _ask() async {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_run()));
  }

  Future<void> _run() async {
    final source = _source;

    if (source == null) {
      return;
    }

    final token = ++_search;
    final query = _query;

    _searching = true;
    notifyListeners();

    try {
      final found = await source.search(query, options);

      if (token != _search || _source != source) {
        return;
      }

      _candidates = found;
      _highlighted = 0;
      _searching = false;

      // Nothing matches and the query has run on into a new word: the trigger
      // was punctuation, and the menu has no business staying up.
      if (found.isEmpty && query.endsWith(' ')) {
        return close();
      }

      notifyListeners();
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to read the ${source.model} suggestions',
        error,
        stackTrace,
      );

      if (token == _search) {
        _searching = false;
        _candidates = const [];
        notifyListeners();
      }
    }
  }

  /// Moves the highlight by [step], wrapping around. Answers whether it could.
  bool moveHighlight(int step) {
    if (!isOpen || _candidates.isEmpty) {
      return false;
    }

    _highlighted = (_highlighted + step) % _candidates.length;
    notifyListeners();

    return true;
  }

  /// Writes the highlighted candidate, or answers false when there is none to
  /// write — the key then goes on to whatever would have had it.
  Future<bool> validate() async {
    if (!isOpen || _candidates.isEmpty) {
      return false;
    }

    await write(_candidates[_highlighted.clamp(0, _candidates.length - 1)]);

    return true;
  }

  /// Replaces the trigger and everything typed after it with [candidate].
  Future<void> write(MentionCandidate candidate) async {
    final editorState = _editorState;
    final source = _source;
    final path = _path;
    final node = path == null ? null : editorState?.getNodeAtPath(path);
    final selection = editorState?.selection;

    if (editorState == null ||
        source == null ||
        node == null ||
        selection == null) {
      return close();
    }

    final caret = selection.end.offset;
    final addressing = mentionAddressing;

    if (addressing == null) {
      // Nothing to point at: an address written without one would resolve
      // nowhere, and a mention that resolves nowhere is worse than plain text.
      _log.warning(
        'Dropped a ${source.model} mention: no addressing registered',
      );

      return close();
    }

    final uri = addressing.encode(model: source.model, id: candidate.id);

    if (uri == null) {
      _log.warning('Dropped a ${source.model} mention: no address to write');

      return close();
    }

    final mention = Mention(
      address: MentionAddress(model: source.model, id: candidate.id, uri: uri),
      label: '${source.trigger}${candidate.label}',
    );

    // One delta rather than two inserts: the second would be bounds-checked
    // against the delta as it stands *before* the transaction, and dropped for
    // running past its end.
    final written = mentionRun(mention)
      // Somewhere to put the caret, and something to type on: a mention is one
      // character wide and cannot be written into.
      ..insert(' ');

    final transaction = editorState.transaction
      ..deleteText(node, _triggerStart, caret - _triggerStart)
      ..insertTextDelta(node, _triggerStart, written);

    close();

    await editorState.apply(transaction);
    await source.onMention?.call(candidate);
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    unawaited(_edits?.cancel());
    _edits = null;

    final onSelection = _onSelection;

    if (onSelection != null) {
      _editorState?.selectionNotifier.removeListener(onSelection);
      _onSelection = null;
    }

    if (_source == null) {
      return;
    }

    _search++;
    _editorState = null;
    _source = null;
    _path = null;
    _query = '';
    _candidates = const [];
    _highlighted = 0;
    _searching = false;
    anchor = null;

    notifyListeners();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
