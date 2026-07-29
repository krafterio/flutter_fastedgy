/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'features/mention/mention_menu.dart' show menuLabel;
import 'rich_text_controls.dart';
import 'rich_text_popover.dart';
import 'rich_text_style.dart';
import 'rich_text_theme.dart';

/// Width of the block list, and how tall it grows before it scrolls.
const _width = 300.0;
const _maxHeight = 260.0;

/// What may be typed after the trigger before it is taken to have been ordinary
/// punctuation after all.
const _maxQuery = 40;

/// The list of blocks a document can insert, and what is being typed to narrow
/// it down.
///
/// The editor ships one of these already, and refuses to open it anywhere but
/// on a desktop — `_showSlashMenu` answers false on a touch platform before
/// doing anything. This is the same idea rebuilt so that a finger gets it too,
/// and rebuilt the way the mention list works rather than as a sheet: the query
/// is typed into the document, so the keyboard stays and the list narrows as it
/// is written, instead of a panel taking the screen and the focus with it.
///
/// It owns no widget — the editor hands it the trigger and the menu reads it —
/// and it holds nothing of the document beyond the position it watches, so a
/// document rebuilt under it simply closes it.
class RichTextSlashController extends ChangeNotifier {
  EditorState? _editorState;
  Path? _path;

  /// Where the trigger begins, and how long it is — one character when "/" was
  /// typed, none when a button opened the list and nothing was written.
  int _start = 0;
  int _trigger = 0;

  String _query = '';
  int _highlighted = 0;
  List<SelectionMenuItem> _items = const [];

  StreamSubscription<EditorTransactionValue>? _edits;
  VoidCallback? _onSelection;

  /// Where the caret stood when the list opened, in global coordinates.
  /// Captured once: a card walking along with the caret as the query grows
  /// would be unreadable.
  Rect? anchor;

  bool get isOpen => _editorState != null;

  String get query => _query;

  int get highlighted => _highlighted;

  /// What is left of the list once what has been typed is taken into account.
  List<SelectionMenuItem> get matches {
    final needle = _query.trim().toLowerCase();

    if (needle.isEmpty) {
      return _items;
    }

    return [
      for (final item in _items)
        if (item.allKeywords.any((keyword) => keyword.contains(needle))) item,
    ];
  }

  /// Opens the list on the caret, [trigger] characters of which were typed to
  /// ask for it.
  void open(
    EditorState editorState,
    List<SelectionMenuItem> items, {
    required int trigger,
    Rect? at,
  }) {
    close();

    final selection = editorState.selection;

    if (selection == null || !selection.isCollapsed) {
      return;
    }

    _editorState = editorState;
    _path = selection.end.path;
    _start = selection.end.offset - trigger;
    _trigger = trigger;
    _items = items;
    _query = '';
    _highlighted = 0;
    anchor = at;

    // A transaction moves the text under the trigger; the selection moves
    // without one every time the caret is put somewhere else. Both can end it.
    _edits = editorState.transactionStream.listen((_) => sync(), onDone: close);
    _onSelection = sync;
    editorState.selectionNotifier.addListener(_onSelection!);

    notifyListeners();
  }

  /// Re-reads the document under the trigger and closes when it no longer says
  /// what it did — the trigger deleted, the caret gone elsewhere, the query run
  /// past what a block is ever called.
  void sync() {
    final editorState = _editorState;
    final path = _path;

    if (editorState == null || path == null) {
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
    final start = _start + _trigger;
    final caret = selection.end.offset;

    if (caret < start || text.length < start) {
      return close();
    }

    if (_trigger > 0 && text.substring(_start, start) != '/') {
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

      // Nothing left and a word has been started: the character was
      // punctuation, and the list has no business staying up.
      if (matches.isEmpty && query.endsWith(' ')) {
        close();
      }
    }
  }

  /// Moves the highlight by [step], wrapping around. Answers whether it could.
  bool moveHighlight(int step) {
    final found = matches;

    if (!isOpen || found.isEmpty) {
      return false;
    }

    _highlighted = (_highlighted + step) % found.length;
    notifyListeners();

    return true;
  }

  /// Applies the highlighted block, or answers false when there is none — the
  /// key then goes on to whatever would have had it.
  Future<bool> validate(BuildContext context) async {
    final found = matches;

    if (!isOpen || found.isEmpty) {
      return false;
    }

    await choose(context, found[_highlighted.clamp(0, found.length - 1)]);

    return true;
  }

  /// Takes back the trigger and the query, then applies [item].
  Future<void> choose(BuildContext context, SelectionMenuItem item) async {
    final editorState = _editorState;
    final path = _path;
    final node = path == null ? null : editorState?.getNodeAtPath(path);
    final selection = editorState?.selection;

    if (editorState == null || node == null || selection == null) {
      return close();
    }

    final caret = selection.end.offset;

    if (caret > _start) {
      await editorState.apply(
        editorState.transaction..deleteText(node, _start, caret - _start),
      );
    }

    // Everything it would have deleted is already gone, and left to itself it
    // would delete back to whatever slash happens to be earlier in the line.
    item
      ..deleteSlash = false
      ..deleteKeywords = false;

    close();

    if (context.mounted) {
      item.handler(editorState, _NoMenu(), context);
    }
  }

  void close() {
    unawaited(_edits?.cancel());
    _edits = null;

    final onSelection = _onSelection;

    if (onSelection != null) {
      _editorState?.selectionNotifier.removeListener(onSelection);
      _onSelection = null;
    }

    if (_editorState == null) {
      return;
    }

    _editorState = null;
    _path = null;
    _items = const [];
    _query = '';
    _highlighted = 0;
    anchor = null;

    notifyListeners();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

/// What the items are handed where there is no menu of the editor's to dismiss.
///
/// They are written against it so they can close it; none of ours touches it,
/// and the type is not optional.
class _NoMenu extends SelectionMenuService {
  @override
  SelectionMenuStyle get style => SelectionMenuStyle.light;

  @override
  Offset get offset => Offset.zero;

  @override
  Alignment get alignment => Alignment.topLeft;

  @override
  Future<void> show() async {}

  @override
  void dismiss() {}

  @override
  (double?, double?, double?, double?) getPosition() =>
      (null, null, null, null);
}

/// Puts the block list under the trigger and keeps it there until the
/// controller says it is over.
///
/// Deliberately focus-free, like the mention list and unlike every other
/// floating surface here: the query is typed into the document, so the caret
/// has to stay exactly where it is. The list only watches.
void showRichTextSlashMenu(
  BuildContext context,
  RichTextSlashController controller,
  EditorState editorState,
) {
  final editorBox = editorState.renderBox;
  final anchor = controller.anchor;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);

  if (editorBox == null || anchor == null || overlay == null) {
    return;
  }

  final editor = editorBox.localToGlobal(Offset.zero) & editorBox.size;

  OverlayEntry? entry;

  void onChanged() {
    if (controller.isOpen) {
      entry?.markNeedsBuild();

      return;
    }

    controller.removeListener(onChanged);
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    // Nothing but the card catches a pointer — the layout box hit-tests its
    // child and nothing more — so a touch in the document still reaches the
    // document, which is what closes the list.
    builder: (context) => Positioned.fill(
      child: CustomSingleChildLayout(
        // Opened on the caret, where no toolbar ever shows: the list sits
        // against the line being typed rather than a toolbar's height away.
        delegate: RichTextPopoverLayout(
          selection: anchor,
          editor: editor,
          width: _width,
          height: _maxHeight,
          avoidToolbar: false,
        ),
        child: _SlashMenu(
          controller: controller,
          editorState: editorState,
          style: editorState.editorStyle.textStyleConfiguration.text,
        ),
      ),
    ),
  );

  controller.addListener(onChanged);
  overlay.insert(entry!);
}

class _SlashMenu extends StatelessWidget {
  final RichTextSlashController controller;
  final EditorState editorState;

  /// The text of the editor the list was opened from, so what is offered reads
  /// at the size of what it will be written into.
  final TextStyle style;

  const _SlashMenu({
    required this.controller,
    required this.editorState,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isOpen) {
          return const SizedBox.shrink();
        }

        final found = controller.matches;

        return _List(
          children: found.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      t('Nothing to insert'),
                      style: menuLabel(
                        style,
                      ).copyWith(color: RichTextTheme.of(context).mutedText),
                    ),
                  ),
                ]
              : [
                  for (final (index, item) in found.indexed)
                    _Row(
                      item: item,
                      editorState: editorState,
                      highlighted: index == controller.highlighted,
                      style: style,
                      onTap: () => unawaited(controller.choose(context, item)),
                    ),
                ],
        );
      },
    );
  }
}

/// The card the rows sit on, sized and scrolled like every other list this
/// document floats.
class _List extends StatefulWidget {
  final List<Widget> children;

  const _List({required this.children});

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x00000000),
      child: Container(
        width: _width,
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        padding: const EdgeInsets.all(4),
        decoration: RichTextTheme.of(context).floatingSurface,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final SelectionMenuItem item;
  final EditorState editorState;
  final bool highlighted;
  final TextStyle style;
  final VoidCallback onTap;

  const _Row({
    required this.item,
    required this.editorState,
    required this.highlighted,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RichTextControls.of(context).tappable(
      context,
      RichTextTapSpec(
        onTap: onTap,
        active: highlighted,
        radius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  // The theme's, never the package's own light set: upstream's
                  // draws a selected glyph in its blue, which belongs to no
                  // application here.
                  child: item.icon(
                    editorState,
                    highlighted,
                    RichTextStyle.slashMenu(RichTextTheme.of(context)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  style: menuLabel(style),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
