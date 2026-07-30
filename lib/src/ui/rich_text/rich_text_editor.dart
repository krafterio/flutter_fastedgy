/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:provider/provider.dart';

import '../icons.dart';
import '../interaction.dart';
import 'rich_text_blank.dart';
import 'rich_text_action.dart';
import 'rich_text_action_bar.dart';
import 'rich_text_blocks.dart';
import 'rich_text_caret.dart';
import 'rich_text_feature.dart';
import 'rich_text_menu.dart';
import 'rich_text_paste.dart';
import 'rich_text_popover.dart';
import 'rich_text_shortcuts.dart';
import 'rich_text_slash_menu.dart';
import 'rich_text_style.dart';
import 'rich_text_theme.dart';
import 'rich_text_toolbar_theme.dart';
import 'rich_text_touch_menu.dart';

/// Rich text on the app's design system (appflowy_editor, MPL-2.0): floating
/// toolbar on the selection, "/" menu to insert blocks, and whatever the
/// [features] add.
///
/// Fills its parent by default, the way a field does — a composer, a reply box.
/// [DocumentEditor] is this same editor given a page's manners: its own
/// scrolling, a centred column, a gutter per block.
///
/// Read-only ([editable] false) drops the toolbar, the shortcuts and the
/// editor's three services — a field that is locked for now, a page shown to
/// someone who may not write in it.
///
/// It is still the whole editor though: a focus scope, an overlay, a scroll
/// controller, and a pass to measure it all. To display many at once — every
/// message of a conversation — use [RichTextViewer], which renders the same
/// blocks with none of that.
class RichTextEditor extends StatefulWidget {
  final EditorState editorState;
  final RichTextFeatures features;

  /// Glyphs swapped on the upstream "/" menu items, keyed by the English label
  /// the editor ships. Empty keeps its own icons.
  final Map<String, IconData> menuIcons;

  final bool editable;

  /// Owns its scrolling instead of taking the height of what it holds. A page
  /// does; a field and a rendered message do not.
  final bool scrollable;

  /// Null fills the parent. A width centres the blocks on a column of it.
  final double? maxWidth;

  /// How tall the field may grow before what is written in it starts to
  /// scroll instead.
  ///
  /// Null grows with its content, which is what a page does and what a field
  /// inside one can afford — the page scrolls. A composer pinned under a thread
  /// cannot: every line typed into it would take one off the thread above.
  ///
  /// Only for a field ([scrollable] false): a page owns its scrolling already.
  final double? maxHeight;

  final EdgeInsets padding;

  /// The text the blocks are drawn at. A page's by default; a field passes
  /// [RichTextStyle.fieldText] so it stands as tall as a plain one would.
  final TextStyle? textStyle;

  /// Rendered above and below the blocks, inside whatever scrolls them.
  final Widget? header;
  final Widget? footer;

  /// Affordances in each block's left margin. None by default: they belong to
  /// a page, not to a field.
  final RichTextBlockActionsBuilder? blockActions;

  /// The toolbar that floats over a selection.
  final bool toolbar;

  /// What the strip offers, from [RichTextActions]' groups. Null takes the
  /// standard set. The features' own actions are appended either way.
  final List<RichTextAction>? actions;

  /// How long the strip stays up.
  ///
  /// Only a docked one — a touch platform's — has any say: a floating strip
  /// hangs off the selected words and cannot outlast them. Null leaves a docked
  /// strip on [RichTextToolbarVisibility.caret], which is what makes it survive
  /// its own block actions and its own undo.
  final RichTextToolbarVisibility? toolbarVisibility;

  /// Room on the strip for what the package cannot know about — an
  /// application's own bottom inset under a navigation bar that floats, a
  /// control of its own at either end of the row.
  final RichTextToolbarSlots toolbarSlots;

  /// The menu that "/" opens. Off leaves the character to be typed.
  final bool slashMenu;

  /// What blocks that menu offers, from the package's own. Null takes them all;
  /// an empty list leaves the menu to the features alone — a field that holds
  /// prose and mentions, and no heading, no table, no rule.
  ///
  /// The features' items are appended either way, the way [actions] works: what
  /// a feature carries is what it carries.
  final List<SelectionMenuItem>? menuItems;

  /// What an empty document reads as while nothing is focused. Null leaves it
  /// blank.
  final String? emptyPlaceholder;

  /// What the empty paragraph holding the cursor reads as.
  final String? hintPlaceholder;

  /// Takes a field emptied of its words back to the paragraph it opens on.
  ///
  /// `# ` turns a block into a heading, and deleting the words back out would
  /// otherwise leave the heading standing in an empty field — its placeholder
  /// where the field's should be, and a block that reads as content to whoever
  /// asks whether anything was written.
  ///
  /// A field's manners, not a page's: on a page an emptied heading is still a
  /// heading, and stays one.
  final bool resetWhenEmpty;

  /// Makes Enter send instead of opening a line — what a composer is written
  /// with. ⌘/Ctrl+Enter then does what Enter would have done: a new block, a
  /// new list item, a line inside a code block.
  ///
  /// Null leaves Enter to the editor. Either way a feature holding the key
  /// keeps it (see [RichTextFeature.holdsEnter]): Enter still writes the
  /// mention being picked rather than sending the message it is going into.
  final VoidCallback? onSubmit;

  const RichTextEditor({
    required this.editorState,
    required this.features,
    super.key,
    this.menuIcons = const {},
    this.editable = true,
    this.scrollable = false,
    this.maxWidth,
    this.maxHeight,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.textStyle,
    this.header,
    this.footer,
    this.blockActions,
    this.toolbar = true,
    this.actions,
    this.toolbarVisibility,
    this.toolbarSlots = RichTextToolbarSlots.none,
    this.slashMenu = true,
    this.menuItems,
    this.emptyPlaceholder,
    this.hintPlaceholder,
    this.resetWhenEmpty = false,
    this.onSubmit,
  });

  @override
  State<RichTextEditor> createState() => RichTextEditorState();
}

class RichTextEditorState extends State<RichTextEditor> {
  late final EditorScrollController scrollController;

  /// Lazily, at first access — which happens while building, where the theme
  /// the builders dress with can be looked up. In initState it cannot.
  late final Map<String, BlockComponentBuilder> _builders =
      _buildBlockComponentBuilders();

  /// The footer, as one item of the page: what [revealFooter] scrolls to.
  final _footerKey = GlobalKey();

  /// Everything the page ends on, footer included: what a tap under the
  /// document must not be mistaken for.
  final _pageEndKey = GlobalKey();

  /// The window a capped field scrolls its blocks behind (see [_revealCaret]).
  final _viewportKey = GlobalKey();

  /// The state whose caret is being followed, to stop following the one it is
  /// swapped for.
  EditorState? _watched;

  StreamSubscription<EditorTransactionValue>? _edits;

  /// The block list a finger opens, held here because the shortcut and the
  /// toolbar button both open the same one.
  final _slash = RichTextSlashController();

  @override
  void initState() {
    super.initState();

    // The editor shows a block's gutter while the block is hovered, and a
    // finger cannot hover: on a touch platform that gate is taken off and the
    // gutter decides for itself which block deserves one — the one being
    // written in (see DocumentGutter).
    //
    // A global of the editor's, read once by each block as it mounts, so it is
    // set here rather than at the gutter: by then every block has already
    // decided. Set and left, never cleared — what it answers is the platform,
    // and that does not change under a running application.
    if (widget.blockActions != null && !hasHoverPointer) {
      forceShowBlockAction = true;
    }

    // shrinkWrap lays the document out as a column of its blocks instead of a
    // scrollable list — what anything that is not a page needs.
    scrollController = EditorScrollController(
      editorState: widget.editorState,
      shrinkWrap: !widget.scrollable,
    );
    _watchEdits();
  }

  @override
  void didUpdateWidget(RichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.editorState != widget.editorState ||
        oldWidget.resetWhenEmpty != widget.resetWhenEmpty) {
      _watchEdits();
    }
  }

  void _watchEdits() {
    unawaited(_edits?.cancel());

    // The caret also moves without a transaction — a tap, an arrow key, a
    // selection put back by hand — and a field that scrolls has to follow it
    // there too.
    _watched?.selectionNotifier.removeListener(_revealCaret);
    _watched = widget.editorState..selectionNotifier.addListener(_revealCaret);

    _edits = widget.resetWhenEmpty || _capped
        ? widget.editorState.transactionStream.listen((_) {
            if (widget.resetWhenEmpty) {
              _resetIfEmpty();
            }

            _revealCaret();
          })
        : null;
  }

  /// Whether the field scrolls behind a window of its own.
  bool get _capped => !widget.scrollable && widget.maxHeight != null;

  /// Brings the caret back into that window.
  ///
  /// A page follows its own: the editor owns the scroll view and scrolls it.
  /// A field with a height of its own does not — the scroll view is the one
  /// wrapped around it below, which nothing inside the editor knows about. So
  /// the line that takes the text past the cap is written out of sight, and the
  /// caret with it.
  ///
  /// After the frame: the line that has just been typed has no size until it is
  /// laid out, and there is nothing to bring back into view before that.
  void _revealCaret() {
    if (!_capped) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final controller = scrollController.scrollController;
      final caret = _caretRect();
      final box = _viewportKey.currentContext?.findRenderObject();

      if (!controller.hasClients ||
          caret == null ||
          box is! RenderBox ||
          !box.attached) {
        return;
      }

      final window = box.localToGlobal(Offset.zero) & box.size;
      final below = caret.bottom - window.bottom;
      final above = window.top - caret.top;
      final by = below > 0 ? below : (above > 0 ? -above : 0.0);

      if (by == 0) {
        return;
      }

      controller.jumpTo(
        (controller.offset + by).clamp(0, controller.position.maxScrollExtent),
      );
    });
  }

  /// Whether the document is back to what an untouched field holds.
  bool get _isBlankParagraph {
    final blocks = widget.editorState.document.root.children;

    return blocks.length == 1 && blocks.first.type == ParagraphBlockKeys.type;
  }

  /// After the frame: the editor is in the middle of the transaction that
  /// brought us here, and the one written back cannot be applied inside it.
  void _resetIfEmpty() {
    if (_isBlankParagraph || !isRichTextBlank(widget.editorState.document)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_isBlankParagraph &&
          isRichTextBlank(widget.editorState.document)) {
        unawaited(clearRichText(widget.editorState));
      }
    });
  }

  @override
  void dispose() {
    unawaited(_edits?.cancel());
    _watched?.selectionNotifier.removeListener(_revealCaret);
    _slash.dispose();

    // A frame late, and it has to be: the list under the editor answers a
    // scroll by writing where its items ended up *after* the frame, and a page
    // being left scrolls one last time. Disposing here lands that write on a
    // dead notifier — the assertion that ended every exit from a document.
    final controller = scrollController;

    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    super.dispose();
  }

  bool get _isBlankDocument {
    final blocks = widget.editorState.document.root.children;

    return blocks.length == 1 &&
        blocks.first.type == ParagraphBlockKeys.type &&
        (blocks.first.delta?.isEmpty ?? true);
  }

  String _paragraphPlaceholder(Node node) =>
      widget.editorState.selection == null && _isBlankDocument
      ? widget.emptyPlaceholder ?? ''
      : widget.hintPlaceholder ?? t('Write, or type “/” to insert a block…');

  Map<String, BlockComponentBuilder>
  _buildBlockComponentBuilders() => richTextBlocks(
    features: widget.features,
    blockActions: widget.blockActions,
    listItemPadding: RichTextTheme.of(context).listItemPadding,
    placeholderText: _paragraphPlaceholder,
    // The package shows a paragraph's placeholder only while the cursor sits in
    // it; a blank document keeps showing its own with no selection at all.
    showPlaceholder: (editorState, node) {
      final selection = editorState.selection;

      return selection == null
          ? _isBlankDocument && widget.emptyPlaceholder != null
          : selection.isSingle && selection.start.path.equals(node.path);
    },
    // The package's page block wraps its blocks in a scroll view of its own,
    // which cannot be laid out where the height is unbounded, and whose scroll
    // controller asserts if it is ever built twice — which measuring the editor
    // does. An editor that does not own its scrolling needs none of it: a plain
    // column measures itself.
    pageBuilder: widget.scrollable ? null : _PlainPageBlockComponentBuilder(),
  );

  /// Every shortcut but a feature's own goes behind the features' guards, so a
  /// block that swallows typing keeps Enter, the markdown triggers and the "/"
  /// menu out of itself.
  List<CharacterShortcutEvent> get _characterShortcuts => [
    ...widget.features.characterShortcuts,
    ...standardCharacterShortcutEvents
        .where((event) => event != slashCommand)
        .map(widget.features.guard),
    if (widget.slashMenu) widget.features.guard(_slashCommand()),
  ];

  /// The "/" menu, in the only form the platform has one.
  ///
  /// The editor's own is desktop and web only — on a touch platform it answers
  /// false and offers nothing, which is what left the character typed and the
  /// placeholder promising a menu that never came. There, the list is asked for
  /// through the application's own control instead.
  CharacterShortcutEvent _slashCommand() {
    final style = RichTextStyle.slashMenu(RichTextTheme.of(context));

    if (hasHoverPointer) {
      return customSlashCommand(
        richTextSlashMenuItems(
          widget.features,
          icons: widget.menuIcons,
          blocks: widget.menuItems,
        ),
        style: style,
      );
    }

    return CharacterShortcutEvent(
      key: 'show the slash menu',
      character: '/',
      handler: (editorState) async {
        final selection = editorState.selection;
        final delta = selection == null
            ? null
            : editorState.getNodeAtPath(selection.start.path)?.delta;

        if (selection == null || !selection.isCollapsed || delta == null) {
          return false;
        }

        // Only where a block could be starting: at the head of the line, or
        // after a space. Anywhere else the character belongs to what is being
        // written — a date, an address, a fraction.
        final before = delta.toPlainText().substring(0, selection.start.offset);

        if (before.isNotEmpty && !before.endsWith(' ')) {
          return false;
        }

        await editorState.insertTextAtPosition('/', position: selection.start);
        _openSlashMenu(trigger: 1);

        return true;
      },
    );
  }

  /// Where the caret stands, or failing that the block it stands in.
  ///
  /// The editor answers with no rectangle at all until its selection service
  /// has drawn one, which it has not always done by the frame after a character
  /// was typed — and a list with nothing to hang from would simply not open.
  Rect? _caretRect() {
    final rect = widget.editorState.selectionRects().firstOrNull;

    if (rect != null) {
      return rect;
    }

    final path = widget.editorState.selection?.start.path;
    final box = path == null
        ? null
        : widget.editorState.getNodeAtPath(path)?.renderBox;

    return box == null || !box.attached
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
  }

  /// Puts the block list on the caret, however it was asked for.
  ///
  /// A frame late: what it hangs from is the caret's rectangle, and the caret
  /// has only just moved — over the character typed, or to wherever the button
  /// was pressed from.
  void _openSlashMenu({required int trigger}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _slash.open(
        widget.editorState,
        richTextSlashMenuItems(
          widget.features,
          icons: widget.menuIcons,
          blocks: widget.menuItems,
        ),
        trigger: trigger,
        at: _caretRect(),
      );

      showRichTextSlashMenu(context, _slash, widget.editorState);
    });
  }

  /// Enter sends, and the modifier opens the line it would have opened.
  ///
  /// Enter is a *character* shortcut to the package — a mention writes itself
  /// on it, a list item continues on it — while these are key bindings, which
  /// the editor offers first. So sending stands aside for a feature holding the
  /// key, and the modifier runs the very shortcuts Enter would have run, guards
  /// included, rather than a new line of its own.
  List<CommandShortcutEvent> get _submitShortcuts => [
    CommandShortcutEvent(
      key: 'submit',
      getDescription: () => t('Send'),
      command: 'enter',
      handler: (editorState) {
        if (widget.features.holdsEnter(editorState)) {
          return KeyEventResult.ignored;
        }

        widget.onSubmit!();

        return KeyEventResult.handled;
      },
    ),
    CommandShortcutEvent(
      key: 'submit new line',
      getDescription: () => t('New line'),
      command: 'cmd+enter',
      windowsCommand: 'ctrl+enter',
      linuxCommand: 'ctrl+enter',
      handler: (editorState) {
        unawaited(_openLine(editorState));

        return KeyEventResult.handled;
      },
    ),
  ];

  /// What Enter does when it is not sending: the first of its shortcuts that
  /// answers for this caret.
  Future<void> _openLine(EditorState editorState) async {
    for (final shortcut in _characterShortcuts) {
      if (shortcut.character != '\n') {
        continue;
      }

      if (await shortcut.handler(editorState)) {
        return;
      }
    }
  }

  /// Brings the foot of the page — the bottom of [RichTextEditor.footer] — to
  /// the bottom edge of the viewport. A page only; a field scrolls with what
  /// holds it.
  ///
  /// Not [Scrollable.ensureVisible]: a page scrolls through a positioned list,
  /// whose viewport answers offsets in coordinates of its own and whose extent
  /// does not follow a footer that grows — a thread taking one more message.
  /// The list is told to place an item instead, which is the one thing it is
  /// built to do: the footer, lifted by its own height so its last line lands
  /// on the bottom edge.
  Future<void> revealFooter({
    Duration duration = const Duration(milliseconds: 220),
  }) async {
    final footer = _footerKey.currentContext?.findRenderObject() as RenderBox?;
    final viewport = context.findRenderObject() as RenderBox?;

    if (!widget.scrollable ||
        footer == null ||
        !footer.attached ||
        viewport == null ||
        viewport.size.height <= 0) {
      return;
    }

    final height = viewport.size.height;

    await scrollController.itemScrollController.scrollTo(
      index:
          widget.editorState.document.root.children.length +
          (widget.header == null ? 0 : 1),
      alignment: (height - footer.size.height) / height,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  /// Where a tap on the page started, so a scroll that ends under the content
  /// is not read as one.
  Offset? _tapStart;

  Widget _underContent(Widget child) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => _tapStart = event.position,
    onPointerUp: (event) {
      final start = _tapStart;
      _tapStart = null;

      if (start != null && (event.position - start).distance <= kTouchSlop) {
        _caretUnderContent(event.position);
      }
    },
    onPointerCancel: (_) => _tapStart = null,
    child: child,
  );

  /// Answers a tap on the empty room under the document: the caret goes to the
  /// end of what is written, and where the last block holds no text — a
  /// picture, a table — it goes into the paragraph that tap adds.
  void _caretUnderContent(Offset at) {
    final last = widget.editorState.document.root.children.lastOrNull;
    final rect = last?.rect;

    if (last == null || rect == null || rect.isEmpty || at.dy <= rect.bottom) {
      return;
    }

    if (_pageEndKey.currentContext?.findRenderObject() case final RenderBox end
        when end.attached) {
      final top = end.localToGlobal(Offset.zero).dy;

      if (at.dy >= top && at.dy <= top + end.size.height) {
        return;
      }
    }

    final target = _deepestLast(last);
    final delta = target.delta;

    if (delta != null) {
      widget.editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: target.path, offset: delta.length)),
        reason: SelectionUpdateReason.uiEvent,
      );

      return;
    }

    unawaited(addParagraphForCaret(widget.editorState, last.path.next));
  }

  /// The last block written under [node], following only blocks that hold text:
  /// a nested list ends on its deepest item, while a table ends on itself —
  /// its cells are not what the page ends with.
  Node _deepestLast(Node node) {
    final child = node.children.lastOrNull;

    return child == null || child.delta == null ? node : _deepestLast(child);
  }

  /// The strip of formatting actions, drawn the way the platform expects.
  ///
  /// Two widgets rather than one placed differently: what a pointer gets is a
  /// compact bar floating over the words, what a thumb gets is a docked one
  /// with targets it can actually hit and menus that open upward. The editor
  /// ships both, with an item set each, and they share no widget.
  /// The strip of formatting actions: our buttons on our glyphs, offering the
  /// same list wherever it is shown.
  ///
  /// Two placements, and only the floating one goes through the editor's own
  /// toolbar — for one thing: knowing when a selection deserves a strip and
  /// putting it in the root overlay. What it would have drawn is replaced, its
  /// items coming in one set for a pointer and another for a thumb, so the same
  /// strip offered different things depending on the device.
  ///
  /// The docked one does not go through it at all: that machinery is wired to
  /// the selection and takes the strip away the moment the caret stops covering
  /// words — which is where every block action and every undo leaves it.
  Widget _toolbar(
    BuildContext context,
    RichTextTheme theme,
    RichTextToolbarTheme toolbarTheme,
    Widget editor,
  ) {
    final actions = [
      ...widget.actions ?? RichTextActions.standard,
      ...widget.features.actions,
    ];
    final themed = Theme(
      data: RichTextStyle.overlayTheme(context, theme),
      child: editor,
    );

    if (toolbarTheme.isDocked) {
      return RichTextDockedToolbar(
        editorState: widget.editorState,
        // The "/" first, and only here: a keyboard types the character, a thumb
        // has no key for it and would otherwise have no way to reach the list
        // of blocks at all. Its own group, so a rule sets it apart from the
        // marks that follow.
        actions: [
          if (widget.slashMenu)
            RichTextAction(
              id: 'blocks',
              glyph: FastEdgyGlyph.slash,
              getLabel: () => t('Insert a block'),
              group: -1,
              isActive: (editorState) => false,
              isEnabled: (editorState) =>
                  editorState.selection?.isCollapsed ?? false,
              // Nothing is written to open it, so nothing has to be taken back
              // if it is closed again.
              run: (editorState) async => _openSlashMenu(trigger: 0),
            ),
          ...actions,
        ],
        visibility: widget.toolbarVisibility ?? RichTextToolbarVisibility.caret,
        slots: widget.toolbarSlots,
        child: themed,
      );
    }

    return FloatingToolbar(
      items: const [],
      style: RichTextStyle.toolbar(toolbarTheme),
      floatingToolbarHeight: toolbarTheme.height,
      toolbarBuilder: (context, _, onDismiss, isMetricsChanged) =>
          placeRichTextToolbar(
            context,
            widget.editorState,
            widget.toolbarSlots.around(
              RichTextActionBar(
                editorState: widget.editorState,
                actions: actions,
                leading: widget.toolbarSlots.leading,
                trailing: widget.toolbarSlots.trailing,
              ),
            ),
            theme: toolbarTheme,
          ),
      editorState: widget.editorState,
      editorScrollController: scrollController,
      textDirection: TextDirection.ltr,
      child: themed,
    );
  }

  /// What the page ends on: the caller's footer, the gap the docked strip
  /// leaves above itself, and whatever the caller asked to put under all that.
  ///
  /// None of it is room the content needs — the strip stands beside the editor
  /// rather than over it, so nothing is ever hidden underneath. It is the room
  /// the content deserves, and it scrolls away like any other trailing padding.
  Widget? _footer(RichTextToolbarTheme toolbarTheme) {
    final footer = switch (widget.footer) {
      final footer? => KeyedSubtree(key: _footerKey, child: footer),
      _ => null,
    };
    final under = widget.toolbarSlots.underContent;
    final gap = widget.editable && widget.toolbar && toolbarTheme.isDocked
        ? toolbarTheme.contentGap
        : 0.0;

    if (under == null && gap == 0) {
      return footer == null
          ? null
          : KeyedSubtree(key: _pageEndKey, child: footer);
    }

    return KeyedSubtree(
      key: _pageEndKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ?footer,
          SizedBox(height: gap),
          ?under,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);
    final toolbarTheme = RichTextToolbarTheme.of(context);

    final editor = AppFlowyEditor(
      editorState: widget.editorState,
      editorScrollController: scrollController,
      blockComponentBuilders: _builders,
      editable: widget.editable,
      shrinkWrap: !widget.scrollable,
      // Nothing to type into, nothing to select, nothing to scroll: the three
      // service layers come off and only the renderer is left.
      disableKeyboardService: !widget.editable,
      disableSelectionService: !widget.editable,
      disableScrollService: !widget.editable,
      // Every shortcut but a feature's own goes behind the features' guards, so
      // a block that swallows typing keeps Enter, the markdown triggers and the
      // "/" menu out of itself.
      characterShortcutEvents: _characterShortcuts,
      // A feature's own first, then what any block selected whole needs — the
      // package walks a delta for both, and these blocks have none.
      commandShortcutEvents: [
        ...widget.features.commandShortcuts,
        if (widget.onSubmit != null) ..._submitShortcuts,
        ...wholeBlockCommands,
        richTextPasteCommand(features: widget.features),
        ...standardCommandShortcutEvents,
      ],
      editorStyle: RichTextStyle.editor(
        theme,
        padding: widget.padding,
        maxWidth: widget.maxWidth,
        textSpanDecorator: widget.features.textSpanDecorator,
        text: widget.textStyle,
      ),
      dropTargetStyle: RichTextStyle.dropTarget(theme),
      header: widget.header,
      footer: _footer(toolbarTheme),
    );

    // The menu a right-click gets is the package's; the one a held press gets
    // is ours, and only where there is no pointer to right-click with.
    final page = widget.editable
        ? _underContent(
            hasHoverPointer
                ? editor
                : RichTextTouchMenu(
                    editorState: widget.editorState,
                    features: widget.features,
                    child: editor,
                  ),
          )
        : editor;

    final whole = widget.editable && widget.toolbar
        ? _toolbar(context, theme, toolbarTheme, page)
        : page;

    // The editor always mounts an Overlay, and an Overlay cannot be laid out
    // where the height is unbounded — a rendered message in a list. Measuring
    // the content first is what the package's own example does, and it is the
    // component's job rather than every caller's. A rendered document is always
    // measured: it takes the height of what it holds wherever it is put.
    if (!widget.editable) {
      return IntrinsicHeight(child: whole);
    }

    if (widget.scrollable) {
      return whole;
    }

    // The arrangement the package asks for when the document lays itself out as
    // a column of its blocks: the scroll view is the caller's, driven by the
    // editor's own controller — which is what the floating toolbar reads to
    // follow the selection through it. Measured inside it, as anything given an
    // unbounded height has to be: the editor mounts an Overlay, and an Overlay
    // laid out against infinity asserts outright.
    if (widget.maxHeight case final maxHeight?) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          key: _viewportKey,
          controller: scrollController.scrollController,
          child: IntrinsicHeight(child: whole),
        ),
      );
    }

    // A field is only measured where it has to be — a composer inside a page
    // that scrolls. The pass runs the whole subtree twice, which a block laying
    // itself out against its constraints (a picture and its handles) refuses
    // outright, so a field given a height of its own is left alone.
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.hasBoundedHeight ? whole : IntrinsicHeight(child: whole),
    );
  }
}

class _PlainPageBlockComponentBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) =>
      _PlainPageBlockComponent(
        key: blockComponentContext.node.key,
        node: blockComponentContext.node,
        header: blockComponentContext.header,
        footer: blockComponentContext.footer,
      );
}

class _PlainPageBlockComponent extends BlockComponentStatelessWidget {
  final Widget? header;
  final Widget? footer;

  const _PlainPageBlockComponent({
    required super.node,
    super.key,
    super.configuration = const BlockComponentConfiguration(),
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final style = editorState.editorStyle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        for (final child in node.children)
          Container(
            constraints: style.maxWidth == null
                ? null
                : BoxConstraints(maxWidth: style.maxWidth!),
            padding: style.padding,
            child: editorState.renderer.build(context, child),
          ),
        ?footer,
      ],
    );
  }
}
