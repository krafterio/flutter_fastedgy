/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:math' show max, min;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../theme/component_theme.dart';
import 'rich_text_style.dart';
import 'rich_text_toolbar_theme.dart';
import 'rich_text_theme.dart';

/// Width every editing card shares, so the ones a document offers line up.
const richTextPopoverWidth = 320.0;

/// Breathing room between the card and what it is anchored to.
const _gap = 6.0;

/// Builds the body of a card, given the callback that closes it.
typedef RichTextPopoverBuilder =
    Widget Function(BuildContext context, VoidCallback dismiss);

/// Opens a card anchored to [selection], for a feature that edits something in
/// place — a link today, whatever comes next.
///
/// Takes care of what every such card needs and none of them should repeat:
/// placement against the selection and the floating toolbar, the chrome, click
/// outside and Escape to close, and holding the editor's focus while it is up
/// so the selection it acts on survives.
///
/// [width] and [height] override the shared size where a feature needs its own
/// — a wider card, or one that has to be told how tall it is rather than take
/// the height of what it holds.
///
/// Returns whether it opened: there is nothing to anchor to before the
/// selection has been laid out.
bool showRichTextPopover(
  BuildContext context,
  EditorState editorState,
  Selection selection, {
  required RichTextPopoverBuilder builder,
  double width = richTextPopoverWidth,
  double? height,
  EdgeInsets? padding,
  bool fitsContent = false,
}) {
  final rects = editorState.selectionRects();
  final editorBox = editorState.renderBox;

  if (rects.isEmpty || editorBox == null) {
    return false;
  }

  final layout = RichTextPopoverLayout(
    selection: rects.first,
    editor: editorBox.localToGlobal(Offset.zero) & editorBox.size,
    width: width,
    height: height,
  );

  final overlayState = Overlay.of(context, rootOverlay: true);

  // The card is built inside an OverlayEntry, which is not under the caller —
  // an ambient theme simply is not found there. Captured here and re-applied
  // below, which is what InheritedTheme exists for.
  final themes = InheritedTheme.capture(
    from: context,
    to: overlayState.context,
  );

  OverlayEntry? overlay;

  // What held the focus before the card took it - the editor, as a rule, which
  // is keeping its selection for the card to act on.
  final held = FocusManager.instance.primaryFocus;

  void dismiss() {
    keepEditorFocusNotifier.decrease();
    overlay?.remove();
    overlay = null;

    if (held != null && held.context != null) {
      held.requestFocus();
    }
  }

  keepEditorFocusNotifier.increase();
  overlay = OverlayEntry(
    builder: (context) => themes.wrap(
      Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
            ),
          ),
          // Fills the overlay so the delegate lays the card out in the same
          // coordinates the selection rect is given in.
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: layout,
              child: _Card(
                width: fitsContent ? null : width,
                height: height,
                padding: padding,
                onDismiss: dismiss,
                child: builder(context, dismiss),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  overlayState.insert(overlay!);

  return true;
}

class _Card extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;

  /// Null where the card takes the width of what it holds — the delegate hands
  /// it a loose constraint, so a menu of four words is four words wide.
  final double? width;

  final double? height;
  final EdgeInsets? padding;

  const _Card({
    required this.child,
    required this.onDismiss,
    required this.width,
    this.height,
    this.padding,
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  /// The card's own scope, taken as it opens.
  ///
  /// The editor holds the focus for as long as the card is up — that is what
  /// [keepEditorFocusNotifier] arranges, so the selection the card acts on
  /// survives. Nothing here would ever be autofocused then, and Escape would go
  /// to the editor, which answers it by dropping its selection and leaving the
  /// card standing. The scope claims the focus instead, and a field of the
  /// card's own is free to take it from there.
  ///
  /// Claimed a frame late: a scope that is not in the focus tree yet drops the
  /// request instead of holding it, unlike a plain node.
  final _scope = FocusScopeNode(debugLabel: 'rich text popover');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      // Above the scope, never inside it: a key reaches the node that holds the
      // focus and then rises through its ancestors.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        },
        child: FocusScope(
          node: _scope,
          child: RichTextSurface(
            width: widget.width,
            height: widget.height,
            padding: widget.padding ?? const EdgeInsets.all(12),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The chrome every surface a document floats shares: the mention list, the
/// link card, the toolbar over a selection.
///
/// One widget rather than a decoration each of them applies, so they cannot
/// drift apart — and so an application restyling [RichTextTheme.floatingSurface]
/// restyles all of them at once.
class RichTextSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double? width;
  final double? height;

  /// What it is drawn on. The shared floating surface unless a caller carries
  /// its own — the toolbar does, so it can be restyled on its own.
  final BoxDecoration? decoration;

  const RichTextSurface({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.width,
    this.height,
    this.decoration,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      // Clipped to its own corners: what scrolls inside a surface has to stop
      // at them, or a row of items runs out past the rounding.
      clipBehavior: Clip.antiAlias,
      decoration: decoration ?? RichTextTheme.of(context).floatingSurface,
      child: child,
    );
  }
}

/// Places the toolbar that floats over a selection, on the surface and through
/// the delegate every other floating thing uses.
///
/// The editor's own placement is a desktop one: it cuts the editor in thirds
/// and hangs the toolbar off the left edge of the selection without ever asking
/// how wide the toolbar is. On a phone it runs off the screen and half its
/// items cannot be reached — which is why the placement goes through the same
/// delegate as every other floating surface, and why a strip a field asked to
/// float on a touch platform lands where it can be read.
///
/// [theme] is resolved by the caller and handed over rather than looked up: the
/// toolbar is built into an overlay, where a theme scoped around the editor —
/// the one saying it floats at all — is nowhere to be found.
///
/// One caveat comes from the editor and cannot be answered here: it drops the
/// toolbar entirely when the selection sits in the top few pixels of the
/// viewport, before this is ever called.
Widget placeRichTextToolbar(
  BuildContext context,
  EditorState editorState,
  Widget bar, {
  required RichTextToolbarTheme theme,
}) {
  final rects = editorState.selectionRects();
  final editorBox = editorState.renderBox;

  if (rects.isEmpty || editorBox == null) {
    return const SizedBox.shrink();
  }

  final editor = editorBox.localToGlobal(Offset.zero) & editorBox.size;

  // Put back around everything it holds, not only used for the surface: the
  // buttons read their own size from it, and in an overlay they would otherwise
  // find whatever the application declared for a strip that docks.
  final strip = ComponentTheme<RichTextToolbarTheme>(
    data: theme,
    child: RichTextSurface(
      padding: theme.padding,
      decoration: theme.surface,
      child: bar,
    ),
  );

  // The first line of the selection that is on screen: a selection running past
  // the top of the viewport has rects with a negative offset, and hanging off
  // one of those puts the toolbar out of sight.
  final visible = rects.where((rect) => rect.top >= 0);
  final anchor = (visible.isEmpty ? rects : visible).reduce(
    (min, current) => current.top < min.top ? current : min,
  );

  return Positioned.fill(
    child: CustomSingleChildLayout(
      delegate: RichTextPopoverLayout(
        selection: anchor,
        editor: editor,
        width: max(0, editor.width - _gap * 2),
        avoidToolbar: false,
        preferAbove: true,
      ),
      child: strip,
    ),
  );
}

/// Places a card under the selected text, flipped above it when there is no
/// room below, kept inside the editor on both axes and always clear of the
/// floating toolbar.
///
/// A layout delegate rather than an offset computed up front: it is handed the
/// card's real size, so nothing about its height has to be guessed. Guessing
/// high would show up as slack between the card and the toolbar, guessing low
/// as the two overlapping.
@visibleForTesting
class RichTextPopoverLayout extends SingleChildLayoutDelegate {
  final Rect selection;
  final Rect editor;
  final double width;

  /// Left to the card's own content when null, which is the usual case — the
  /// delegate is handed the resulting height either way.
  final double? height;

  /// Whether to leave the floating toolbar room above the selection.
  ///
  /// The toolbar only ever shows over a *range*, so a surface that opens on the
  /// caret — the mention list, which opens on the trigger just typed — says no
  /// and sits against the line it belongs to instead of a toolbar's height
  /// away from it.
  final bool avoidToolbar;

  /// Above the selection first, below it when there is no room — which is what
  /// a toolbar acting on the selected words does, so it does not cover them.
  /// A card offering something to read or fill in does the opposite.
  final bool preferAbove;

  const RichTextPopoverLayout({
    required this.selection,
    required this.editor,
    this.width = richTextPopoverWidth,
    this.height,
    this.avoidToolbar = true,
    this.preferAbove = false,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(width, height ?? constraints.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = editor.right - childSize.width - _gap;
    final left = selection.left.clamp(
      editor.left + _gap,
      maxLeft > editor.left ? maxLeft : editor.left,
    );

    // The toolbar sits right above the selection, and drops below it when the
    // selection is too close to the top to fit — the same test it makes itself.
    final toolbarBelow =
        avoidToolbar && selection.top < RichTextStyle.toolbarHeight;
    final below =
        selection.bottom +
        _gap +
        (toolbarBelow ? RichTextStyle.toolbarSpan : 0);

    final ceiling =
        selection.top -
        _gap -
        (avoidToolbar && !toolbarBelow ? RichTextStyle.toolbarHeight : 0);
    final above = ceiling - childSize.height;

    if (preferAbove) {
      return above >= 0
          ? Offset(left, above)
          : Offset(left, min(below, max(0, editor.bottom - childSize.height)));
    }

    if (below + childSize.height <= editor.bottom) {
      return Offset(left, below);
    }

    return Offset(left, max(0, above));
  }

  @override
  bool shouldRelayout(RichTextPopoverLayout oldDelegate) =>
      oldDelegate.selection != selection ||
      oldDelegate.editor != editor ||
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.avoidToolbar != avoidToolbar ||
      oldDelegate.preferAbove != preferAbove;
}
