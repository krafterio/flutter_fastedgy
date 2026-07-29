/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:provider/provider.dart';

import 'rich_text_blank.dart';
import 'rich_text_blocks.dart';
import 'rich_text_feature.dart';
import 'rich_text_menu.dart';
import 'rich_text_shortcuts.dart';
import 'rich_text_style.dart';
import 'rich_text_theme.dart';
import 'rich_text_toolbar.dart';

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
/// message of a conversation — use [RichTextView], which renders the same
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

  /// What it offers, from [RichTextToolbar]'s groups. Null takes the standard
  /// set. The features' own items are appended either way.
  final List<ToolbarItem>? toolbarItems;

  /// The menu that "/" opens. Off leaves the character to be typed.
  final bool slashMenu;

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
    this.toolbarItems,
    this.slashMenu = true,
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
  late final Map<String, BlockComponentBuilder> _builders;

  /// The footer, as one item of the page: what [revealFooter] scrolls to.
  final _footerKey = GlobalKey();

  StreamSubscription<EditorTransactionValue>? _edits;

  @override
  void initState() {
    super.initState();
    // shrinkWrap lays the document out as a column of its blocks instead of a
    // scrollable list — what anything that is not a page needs.
    scrollController = EditorScrollController(
      editorState: widget.editorState,
      shrinkWrap: !widget.scrollable,
    );
    _builders = _buildBlockComponentBuilders();
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
    _edits = widget.resetWhenEmpty
        ? widget.editorState.transactionStream.listen((_) => _resetIfEmpty())
        : null;
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
    scrollController.dispose();
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
    if (widget.slashMenu)
      widget.features.guard(
        customSlashCommand(
          richTextSlashMenuItems(widget.features, icons: widget.menuIcons),
          style: RichTextStyle.slashMenu(RichTextTheme.of(context)),
        ),
      ),
  ];

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

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

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
      footer: switch (widget.footer) {
        final footer? => KeyedSubtree(key: _footerKey, child: footer),
        _ => null,
      },
    );

    final whole = widget.editable && widget.toolbar
        ? FloatingToolbar(
            items: [
              ...widget.toolbarItems ?? RichTextToolbar.standard,
              ...widget.features.toolbarItems,
            ],
            style: RichTextStyle.toolbar(theme),
            decoration: theme.floatingSurface,
            // Shared with whatever has to place itself clear of the toolbar.
            floatingToolbarHeight: RichTextStyle.toolbarHeight,
            editorState: widget.editorState,
            editorScrollController: scrollController,
            textDirection: TextDirection.ltr,
            child: Theme(
              data: RichTextStyle.overlayTheme(context, theme),
              child: editor,
            ),
          )
        : editor;

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
