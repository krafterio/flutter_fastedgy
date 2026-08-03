/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

import '../icons.dart';
import '../theme/component_theme.dart';
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

/// Which edge a docked strip sits on.
enum RichTextToolbarEdge {
  /// Under the words, above the keyboard: where a phone puts its own, and where
  /// a page wants it — the strip stands at the foot of what is being read.
  bottom,

  /// Over the words.
  ///
  /// What a field that grows with what is written wants: a strip appearing
  /// under it takes the field's foot down, or its head up, by its own height,
  /// and the line being written jumps under the thumb about to touch it. Above
  /// them nothing already written moves.
  top,
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
  /// The editor already reserves the strip's own height there, so nothing is
  /// ever hidden underneath — this is for the breathing room a caller wants on
  /// top of that, so the last line does not end up flush against the buttons.
  final Widget? underContent;

  const RichTextToolbarSlots({
    this.leading,
    this.trailing,
    this.above,
    this.below,
    this.underContent,
  });

  /// What a caller that asked for nothing gets.
  static const none = RichTextToolbarSlots();

  /// Whether the room the system asks for at the bottom of the screen is spoken
  /// for by a band of the caller's own. Only ever asked while the strip is held
  /// there — parked on the editor it is nobody's business (see
  /// [RichTextDockedToolbar]).
  bool get holdsBottom => below != null;

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

/// The strip that sticks to the bottom of the editor.
///
/// Its own widget rather than the editor's floating toolbar given a different
/// place to stand: that one is wired to the selection — it takes itself away
/// the moment the caret stops covering words, which is what every block action
/// and every undo leaves behind. Docked, there is nothing to anchor to and
/// nothing to get out of the way of, so it stays and [visibility] says how long.
///
/// Sticky, in the sense the word has on the web: it sits at the foot of the
/// editor, and while that foot is below the screen it stays at the screen's
/// instead — above the keyboard. Scroll far enough for the end of the document
/// to come up and the strip parks on it and travels with it.
///
/// The room it needs is reserved at the foot of the content by the editor (see
/// `RichTextEditor`), so the last line can always be scrolled clear of it: the
/// two states then look like one, the strip taking that reserved band when it
/// parks and passing over it when it is pinned.
///
/// Drawn inside the editor rather than in the overlay the floating one uses: an
/// entry that outlives a selection would also outlive the screen it belongs to
/// and hang over whatever was pushed on top of it.
class RichTextDockedToolbar extends StatefulWidget {
  final EditorState editorState;
  final List<RichTextAction> actions;
  final RichTextToolbarVisibility visibility;

  /// What the application wanted room for on the strip.
  final RichTextToolbarSlots slots;

  /// Which edge it sits on.
  final RichTextToolbarEdge edge;

  /// The editor it is docked to.
  final Widget child;

  /// Told how tall it turned out, so the content can reserve exactly that at
  /// its foot — bands and system edge included, which no sum of theme values
  /// could know.
  final ValueNotifier<double>? measured;

  const RichTextDockedToolbar({
    required this.editorState,
    required this.actions,
    required this.child,
    super.key,
    this.visibility = RichTextToolbarVisibility.caret,
    this.slots = RichTextToolbarSlots.none,
    this.edge = RichTextToolbarEdge.bottom,
    this.measured,
  });

  @override
  State<RichTextDockedToolbar> createState() => _RichTextDockedToolbarState();
}

class _RichTextDockedToolbarState extends State<RichTextDockedToolbar>
    with WidgetsBindingObserver {
  final _editorKey = GlobalKey();
  final _stripKey = GlobalKey();

  /// How far the editor's foot runs past the bottom of the screen. Zero once it
  /// is inside it, which is what parks the strip on the editor rather than on
  /// the screen.
  double _overflow = 0;

  /// Whether it is held at the bottom of the screen rather than parked on the
  /// editor. Not `_overflow > 0`: a page fills the viewport, so its foot lands
  /// exactly on the screen's — held there, and owing the system its band all
  /// the same.
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The keyboard coming up moves the screen's bottom, not the editor's.
  @override
  void didChangeMetrics() => _scheduleMeasure();

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  void _measure() {
    _measureStrip();

    final box = _editorKey.currentContext?.findRenderObject();

    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }

    final media = MediaQuery.of(context);
    final foot = box.localToGlobal(Offset(0, box.size.height)).dy;
    final screen = media.size.height - media.viewInsets.bottom;
    final overflow = foot - screen;

    final settled = overflow > 0 ? overflow : 0.0;
    final pinned = foot >= screen - 0.5;

    if ((settled - _overflow).abs() > 0.5 || pinned != _pinned) {
      setState(() {
        _overflow = settled;
        _pinned = pinned;
      });
    }
  }

  /// What the strip stands in, for the band the content keeps at its foot.
  ///
  /// Zero while it is not up: there is nothing to keep clear of. Never less than
  /// what the theme gives it while it is — what a caller put in the bands can
  /// only be measured, but a band that waits for a measurement is zero on the
  /// frame the strip appears, and the strip stands on the line being written
  /// until something else asks for another one.
  void _measureStrip() {
    final notifier = widget.measured;

    if (notifier == null) {
      return;
    }

    final box = _stripKey.currentContext?.findRenderObject();
    final measured = box is RenderBox && box.attached && box.hasSize
        ? box.size.height
        : 0.0;
    final height = _showing ? max(measured, _declared) : 0.0;

    if ((height - notifier.value).abs() > 0.5) {
      notifier.value = height;
    }
  }

  bool get _atTop => widget.edge == RichTextToolbarEdge.top;

  /// The surface with its rule on the side the words are on.
  ///
  /// A docked strip carries one line telling it apart from what it sits beside,
  /// and the theme draws it for a strip under them. Over them it belongs on the
  /// other side.
  BoxDecoration _surface(RichTextToolbarTheme theme) {
    final border = theme.surface.border;

    if (!_atTop || border is! Border) {
      return theme.surface;
    }

    return theme.surface.copyWith(
      border: Border(top: border.bottom, bottom: border.top),
    );
  }

  /// The strip at the height the theme gives it, bands and system edge aside:
  /// what the content owes it before anything has been measured.
  double get _declared {
    final theme = RichTextToolbarTheme.of(context);

    return theme.height + theme.padding.vertical;
  }

  /// Whether the strip is up, as the last build left it. Read by the measuring,
  /// which runs after that frame rather than during it.
  bool _showing = false;

  bool _shows(Selection? selection) => switch (widget.visibility) {
    RichTextToolbarVisibility.always => true,
    RichTextToolbarVisibility.caret => selection != null,
    RichTextToolbarVisibility.selection =>
      selection != null && !selection.isCollapsed,
  };

  @override
  Widget build(BuildContext context) {
    final theme = RichTextToolbarTheme.of(context);
    final system = MediaQuery.viewPaddingOf(context).bottom;

    // Measured on every frame the editor lays out again: what is written into
    // it, what scrolls under it and what the keyboard does to the screen all
    // move the foot this strip follows.
    _scheduleMeasure();

    // The editor is handed through rather than rebuilt: only the strip answers
    // the caret moving.
    return ValueListenableBuilder<Selection?>(
      valueListenable: widget.editorState.selectionNotifier,
      child: KeyedSubtree(key: _editorKey, child: widget.child),
      builder: (context, selection, editor) {
        // The strip going up or coming down is the whole of what the content
        // has to keep clear at its foot, and this is the only thing that runs
        // when it does: the state's own build answers the editor moving, not
        // the caret. A field that only shows the strip over a selection was
        // reserving nothing, and the strip stood on the line being written.
        _showing = _shows(selection);
        _scheduleMeasure();

        return NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _scheduleMeasure();

            return false;
          },
          child: Stack(
            children: [
              editor!,
              if (_shows(selection))
                Positioned(
                  left: 0,
                  right: 0,
                  // Zero parks it on the editor's own foot; anything else holds
                  // it at the bottom of the screen while that foot is below.
                  // Nothing to follow at the head: what the keyboard moves is
                  // the bottom of the screen.
                  top: _atTop ? 0 : null,
                  bottom: _atTop ? null : _overflow,
                  child: RichTextSurface(
                    key: _stripKey,
                    padding: theme.padding.copyWith(
                      // The surface reaches the edge, its buttons do not: pinned
                      // with the keyboard down, the last strip of the screen
                      // belongs to the system — on iOS the home indicator takes
                      // the first tap there. Parked on the editor, or standing
                      // over the words, there is no edge to leave alone.
                      bottom:
                          theme.padding.bottom +
                          (!_atTop && _pinned && !widget.slots.holdsBottom
                              ? system
                              : 0),
                    ),
                    decoration: _surface(theme),
                    child: widget.slots.around(
                      ComponentTheme<RichTextToolbarTheme>(
                        // Its buttons and nothing more at the head of a field:
                        // the row is taller than they are, which at the foot of
                        // the screen reads as breathing room and under a rule
                        // reads as a band of nothing.
                        data: _atTop
                            ? theme.copyWith(height: theme.itemSize)
                            : theme,
                        child: RichTextActionBar(
                          editorState: widget.editorState,
                          actions: widget.actions,
                          leading: widget.slots.leading,
                          trailing: widget.slots.trailing,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
