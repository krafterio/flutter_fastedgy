/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

import '../icons.dart';
import 'rich_text_action.dart';
import 'rich_text_clipboard.dart';
import 'rich_text_controls.dart';
import 'rich_text_popover.dart';
import 'rich_text_theme.dart';
import 'rich_text_toolbar_theme.dart';

/// When the strip of formatting actions is up.
///
/// A floating strip has no say: it hangs off the selected words, so it can only
/// ever be there while there are some. A docked one is pinned to the bottom
/// whatever the caret is doing, and gets to choose.
enum RichTextToolbarVisibility {
  /// Only while words are selected.
  selection,

  /// Whenever the caret is in the document, words selected or not.
  ///
  /// What a docked strip does unless told otherwise: half of what it offers —
  /// the lists, the headings, undo — acts on the block the caret is in and
  /// needs nothing selected. Undo in particular leaves a bare caret behind, and
  /// a strip that waited for a selection took itself away the moment it was
  /// used.
  caret,

  /// Always, whether the document is being written in or not.
  always,
}

/// Room a caller gets on the formatting strip, for what the package has no way
/// of knowing about.
@immutable
class RichTextToolbarSlots {
  /// At the ends of the row, and travelling with it: they are part of what
  /// slides, not brackets around it.
  final Widget? leading;
  final Widget? trailing;

  /// Full-width bands above and below the row, inside the same surface.
  ///
  /// [below] also takes the bottom edge over: a docked strip leaves the last
  /// pixels of the screen to the system — the home indicator takes the first
  /// tap there — and stops leaving them once somebody else is holding that
  /// space. An application whose navigation floats over the bottom knows what
  /// it needs there; the package only knows what the system asks for.
  final Widget? above;
  final Widget? below;

  /// At the foot of what scrolls, under the last block and the footer.
  ///
  /// The strip itself already takes its room out of the page rather than
  /// hanging over it, so nothing is ever hidden underneath — this is for the
  /// breathing room a caller wants on top of that, so the last line does not
  /// end up flush against the buttons.
  final Widget? underContent;

  /// Whether the strip ends the screen.
  ///
  /// True unless said otherwise: a docked strip usually does, and the last
  /// pixels of the screen belong to the system — which is what the band under
  /// its buttons is for.
  ///
  /// A field says false. A composer in a sheet, a description in a form: the
  /// application has controls of its own under it, the system's edge is
  /// somebody else's problem, and the band reserved for it lands in the middle
  /// of the page as a gap nothing explains.
  final bool reachesBottomEdge;

  const RichTextToolbarSlots({
    this.leading,
    this.trailing,
    this.above,
    this.below,
    this.underContent,
    this.reachesBottomEdge = true,
  });

  /// What a caller that asked for nothing gets.
  static const none = RichTextToolbarSlots();

  /// Whether the room the system asks for at the bottom is spoken for — by a
  /// band of the caller's own, or by whatever it put the strip above.
  bool get holdsBottom => below != null || !reachesBottomEdge;

  /// The strip with its bands, or the strip alone when there are none.
  Widget around(Widget bar) => above == null && below == null
      ? bar
      : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [?above, bar, ?below],
        );
}

/// The strip of formatting actions, drawn with the application's own buttons.
///
/// Nothing of the underlying editor's toolbar is here: what it offers is the
/// same list wherever it is shown — floating over a selection with a pointer,
/// docked above the keyboard under a thumb — so the two cannot drift apart the
/// way two sets of items do.
class RichTextActionBar extends StatefulWidget {
  final EditorState editorState;
  final List<RichTextAction> actions;

  /// What the caller put at either end of the row.
  final Widget? leading;
  final Widget? trailing;

  /// Padding around the row of buttons.
  final EdgeInsets padding;

  /// Called once an action has run, for a strip that stands only as long as
  /// what raised it — the one a held press brings up over a bare caret.
  final VoidCallback? onRun;

  const RichTextActionBar({
    required this.editorState,
    required this.actions,
    super.key,
    this.leading,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.onRun,
  });

  @override
  State<RichTextActionBar> createState() => _RichTextActionBarState();
}

class _RichTextActionBarState extends State<RichTextActionBar> {
  /// Where the caret was when the finger landed on the strip.
  ///
  /// Taken then rather than read when the action runs: anything touched outside
  /// the text may collapse the selection first, and by the time the action ran
  /// there was nothing left to apply it to — the button looked dead. Down is
  /// the last moment it is still whatever the writer left it as.
  Selection? _snapshot;

  final _scroll = ScrollController();

  /// Where the finger was at the last move, when one is down.
  double? _lastX;

  EditorState get editorState => widget.editorState;

  @override
  void initState() {
    super.initState();

    // As the strip appears, and again whenever the caret moves: whoever copied
    // something did it between two of those, and asking is cheap and silent
    // (see refreshRichTextClipboard).
    unawaited(refreshRichTextClipboard());
    editorState.selectionNotifier.addListener(_onSelectionMoved);
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(_onSelectionMoved);
    _scroll.dispose();
    super.dispose();
  }

  void _onSelectionMoved() => unawaited(refreshRichTextClipboard());

  @override
  Widget build(BuildContext context) {
    final theme = RichTextToolbarTheme.of(context);

    // Rebuilt as the selection moves and as the clipboard fills: what is on and
    // what is reachable are read from where the caret is and from what there is
    // to paste into it.
    return ValueListenableBuilder<bool>(
      valueListenable: richTextClipboardHasContent,
      builder: (context, _, _) => ValueListenableBuilder<Selection?>(
        valueListenable: editorState.selectionNotifier,
        builder: (context, selection, child) {
          return SizedBox(
            height: theme.height,
            // A longer list than the room it was given slides sideways rather
            // than spilling out of it — the usual case on a phone.
            //
            // Moved by hand, from the raw pointer, for the reason the buttons are
            // pressed that way: the strip hangs in an overlay above an editor
            // that claims what it can, and a drag recognizer here has to win an
            // arena to move anything. It lost on a real device while winning in
            // every harness. Nothing is arbitrated now — a finger that travels
            // carries the strip with it.
            child: Listener(
              onPointerDown: (event) {
                _lastX = event.position.dx;
                _snapshot = editorState.selection;
              },
              onPointerMove: _onMove,
              onPointerUp: (_) => _lastX = null,
              onPointerCancel: (_) => _lastX = null,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false, overscroll: false),
                child: SingleChildScrollView(
                  controller: _scroll,
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  padding: widget.padding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _children(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onMove(PointerMoveEvent event) {
    final last = _lastX;

    if (last == null || !_scroll.hasClients) {
      return;
    }

    _lastX = event.position.dx;

    final position = _scroll.position;
    final target = position.pixels - (event.position.dx - last);

    _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  /// The row: what the caller put at the head, the actions with a rule between
  /// groups, and what the caller put at the tail. The ends travel with the rest
  /// rather than bracketing it — a strip too long to fit slides whole.
  List<Widget> _children(BuildContext context) {
    final children = <Widget>[?widget.leading];
    int? previous;

    for (final action in widget.actions) {
      if (previous != null && action.group != previous) {
        children.add(_Rule(height: RichTextToolbarTheme.of(context).height));
      }

      children.add(
        _Button(
          editorState: editorState,
          action: action,
          onPressed: () => _run(action),
        ),
      );
      previous = action.group;
    }

    return [...children, ?widget.trailing];
  }

  /// Puts the caret back where it was before acting, and leaves it there: what
  /// was worked on stays selected, so a second mark can be added without
  /// picking the words again.
  Future<void> _run(RichTextAction action) async {
    final snapshot = _snapshot;

    if (snapshot != null && editorState.selection != snapshot) {
      editorState.selection = snapshot;
    }

    await action.run(editorState);

    widget.onRun?.call();
  }
}

/// The strip pinned to the bottom of the editor, above the keyboard.
///
/// Its own widget rather than the editor's floating toolbar given a different
/// place to stand: that one is wired to the selection — it takes itself away
/// the moment the caret stops covering words, which is what every block action
/// and every undo leaves behind. Docked, there is nothing to anchor to and
/// nothing to get out of the way of, so it stays and [visibility] says how long.
///
/// Drawn inside the editor rather than in the overlay the floating one uses: an
/// entry that outlives a selection would also outlive the screen it belongs to
/// and hang over whatever was pushed on top of it.
class RichTextDockedToolbar extends StatelessWidget {
  final EditorState editorState;
  final List<RichTextAction> actions;
  final RichTextToolbarVisibility visibility;

  /// What the application wanted room for on the strip.
  final RichTextToolbarSlots slots;

  /// The editor it is docked to. The strip stands at the bottom of it, which is
  /// the bottom of the screen for a page and of the field for a field.
  final Widget child;

  const RichTextDockedToolbar({
    required this.editorState,
    required this.actions,
    required this.child,
    super.key,
    this.visibility = RichTextToolbarVisibility.caret,
    this.slots = RichTextToolbarSlots.none,
  });

  bool _shows(Selection? selection) => switch (visibility) {
    RichTextToolbarVisibility.always => true,
    RichTextToolbarVisibility.caret => selection != null,
    RichTextToolbarVisibility.selection =>
      selection != null && !selection.isCollapsed,
  };

  @override
  Widget build(BuildContext context) {
    final theme = RichTextToolbarTheme.of(context);
    // Zero once a Scaffold has resized around the keyboard, which is the usual
    // case and leaves the editor ending right above it. Where nothing resized,
    // the editor runs under the keyboard and this is how far up to come.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final system = MediaQuery.viewPaddingOf(context).bottom;

    // The editor is handed through rather than rebuilt: only the strip answers
    // the caret moving.
    //
    // Beside the editor rather than over it: a strip laid over the bottom hides
    // the last lines of whatever is under it, and no amount of padding at the
    // foot of the document is ever exactly its height — the bands an
    // application adds to it are the application's, and their height is not
    // ours to guess. Taking the room instead of borrowing it makes the question
    // go away: the editor is laid out in what is left, and scrolls to its own
    // end inside it.
    return ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      child: child,
      builder: (context, selection, editor) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Loose rather than expanded: a page fills what it is given, a field
          // takes the height of what it holds, and this has to serve both.
          Flexible(child: editor!),
          // The surface reaches the edge, its buttons do not: with the keyboard
          // down the last strip of the screen belongs to the system — on iOS
          // the home indicator takes the first tap there, and a button sitting
          // in it reads as dead. Unless the application put something of its
          // own down there, in which case that space is spoken for.
          if (_shows(selection))
            Padding(
              // Where nothing resized around the keyboard, the column runs
              // under it and this is how far up to come.
              padding: EdgeInsets.only(bottom: keyboard),
              child: RichTextSurface(
                padding: theme.padding.copyWith(
                  bottom:
                      theme.padding.bottom +
                      (keyboard > 0 || slots.holdsBottom ? 0 : system),
                ),
                decoration: theme.surface,
                child: slots.around(
                  RichTextActionBar(
                    editorState: editorState,
                    actions: actions,
                    leading: slots.leading,
                    trailing: slots.trailing,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fires on the pointer rather than through a tap recognizer.
///
/// A button of this strip sits inside a horizontal scroll view and over an
/// editor that answers the first contact by moving the selection: a tap has to
/// win an arena against both, and the finger only has to slide a pixel for it
/// to lose. Nothing is arbitrated here — the press is remembered, and the
/// release fires it unless the finger travelled, which is what a drag is.
class _Button extends StatefulWidget {
  final EditorState editorState;
  final RichTextAction action;
  final VoidCallback onPressed;

  const _Button({
    required this.editorState,
    required this.action,
    required this.onPressed,
  });

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  static const _slop = 12.0;

  Offset? _down;

  EditorState get editorState => widget.editorState;
  RichTextAction get action => widget.action;

  void _onDown(PointerDownEvent event) => _down = event.position;

  void _onUp(PointerUpEvent event) {
    final down = _down;
    _down = null;

    if (down != null && (event.position - down).distance <= _slop) {
      widget.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);
    final toolbar = RichTextToolbarTheme.of(context);
    final enabled = action.isEnabled(editorState);
    final active = action.isActive(editorState);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: enabled ? _onDown : null,
      onPointerUp: enabled ? _onUp : null,
      onPointerCancel: (_) => _down = null,
      child: RichTextControls.of(context).tappable(
        context,
        RichTextTapSpec(
          // The press is handled above; the control draws the chrome and says
          // what is on.
          onTap: () {},
          active: active,
          tooltip: action.getLabel(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: toolbar.itemSpacing / 2),
            child: SizedBox(
              width: toolbar.itemSize,
              height: toolbar.itemSize,
              child: Icon(
                FastEdgyIcons.of(context)[action.glyph],
                size: toolbar.iconSize,
                color: enabled
                    ? (active ? toolbar.activeColor : toolbar.iconColor)
                    : theme.subtleBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What tells one group of actions from the next.
class _Rule extends StatelessWidget {
  final double height;

  const _Rule({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height / 2,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: RichTextTheme.of(context).subtleBorder,
    );
  }
}
