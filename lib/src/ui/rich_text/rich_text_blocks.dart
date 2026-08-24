/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import 'rich_text_feature.dart';

/// Builds what hangs in a block's left margin, given the block and the builder
/// that renders it — the latter being what a drag has to draw as feedback.
typedef RichTextBlockActionsBuilder = Widget Function(
  BlockComponentContext blockContext,
  BlockComponentBuilder builder,
);

/// The blocks a document can hold: the package's, plus what the [features] add
/// or override, all dressed the same way.
///
/// Shared by the editor and the view so a block looks and behaves identically
/// whether it is being written or merely read.
/// What an empty heading reads as while the caret sits in it.
///
/// The package hangs `Heading 1` off it, in English, from a string written into
/// its own source — the one label in the editor no application could reach.
String _headingPlaceholder(Node node) =>
    switch (node.attributes[HeadingBlockKeys.level]) {
      1 => t('Heading 1'),
      2 => t('Heading 2'),
      _ => t('Heading 3'),
    };

Map<String, BlockComponentBuilder> richTextBlocks({
  required RichTextFeatures features,
  RichTextBlockActionsBuilder? blockActions,
  ShowPlaceholder? showPlaceholder,
  String Function(Node node)? placeholderText,
  BlockComponentBuilder? pageBuilder,
  EdgeInsets listItemPadding = const EdgeInsets.symmetric(vertical: 3),
  TextStyle Function(int level)? headingText,
  EdgeInsets Function(int level)? headingMargin,
  EdgeInsets? dividerPadding,
}) {
  final builders = {...standardBlockComponentBuilderMap, ...features.builders};
  final heading = builders[HeadingBlockKeys.type];
  final divider = builders[DividerBlockKeys.type];

  // The package sizes its headings in pixels from its own source, and a builder
  // is the only way a theme reaches them.
  if (headingText != null && heading is HeadingBlockComponentBuilder) {
    builders[HeadingBlockKeys.type] = HeadingBlockComponentBuilder(
      configuration: heading.configuration,
      textStyleBuilder: headingText,
    );
  }

  // The package pads its rule from inside, with a band of its own the theme
  // cannot reach: the line alone is left here, and the air around it becomes
  // the block's padding like a heading's is its margin.
  if (dividerPadding != null && divider is DividerBlockComponentBuilder) {
    builders[DividerBlockKeys.type] = DividerBlockComponentBuilder(
      configuration: divider.configuration,
      lineColor: divider.lineColor,
      wrapper: divider.wrapper,
      height: 1,
    );
  }

  if (showPlaceholder != null) {
    // Never inside a table: a cell is a column of its own, and the hint wrapped
    // over four lines in it. The package measures a row from what its cells
    // draw, so the placeholder was pushing the whole row open — and the height
    // it left behind stayed once the hint had gone.
    builders[ParagraphBlockKeys.type] = ParagraphBlockComponentBuilder(
      showPlaceholder: (editorState, node) =>
          !_inTable(node) && showPlaceholder(editorState, node),
    );
  }

  if (pageBuilder != null) {
    builders[PageBlockKeys.type] = pageBuilder;
  }

  for (final type in builders.keys.toList()) {
    if (type == PageBlockKeys.type) {
      continue;
    }

    // Never the package's own instance: it hands out one per block type, from a
    // map built once, and a builder holds its dressing in mutable fields. Two
    // editors on the same screen (a flow's description and the messages
    // rendered under it) would take turns writing those fields, the last one
    // mounted deciding whether the other's blocks hang a gutter in their
    // margin. Each editor takes a builder of its own instead, which carries its
    // own dressing and lends it to the shared one for the moment it builds.
    final builder = _ScopedBlockComponentBuilder(builders[type]!);
    builders[type] = builder;

    builder.configuration = builder.configuration.copyWith(
      padding: (_) => switch (type) {
        DividerBlockKeys.type when dividerPadding != null => dividerPadding,
        _ when _listTypes.contains(type) => listItemPadding,
        _ => const EdgeInsets.symmetric(vertical: 3),
      },
      // Null leaves the package's own, which every block but a heading keeps.
      margin: type == HeadingBlockKeys.type && headingMargin != null
          ? (node) => _headingMargin(node, headingMargin)
          : null,
      placeholderText: switch (type) {
        ParagraphBlockKeys.type => placeholderText,
        HeadingBlockKeys.type => _headingPlaceholder,
        _ => null,
      },
    );
    // Nothing hangs in a cell's margin: the table has handles of its own for
    // its rows and columns, and ours were landing on top of them — a cell has
    // no margin to put them in anyway.
    builder.showActions = (node) => blockActions != null && !_inTable(node);

    if (blockActions != null) {
      // The builder is handed over with the context: whatever renders in the
      // margin usually has to render the block itself too, to drag it.
      builder.actionBuilder = (blockContext, _) =>
          blockActions(blockContext, builder);
    }
  }

  return builders;
}

/// Which editor built a node, so what a block reads back long after its build
/// comes from the editor holding it rather than from whoever wrote last on the
/// shared builder.
///
/// Weak on the node, so a block the document has dropped is forgotten with it.
final _scopeOf = Expando<_ScopedBlockComponentBuilder>('rich text block scope');

/// What the package's blocks call to fill their margin — one function for every
/// editor, asking the node itself whose gutter it should hang.
///
/// A block reads `actionBuilder` off its builder at the moment its margin
/// draws, not at the moment it is built: the first hover on a page, minutes
/// later, reached whatever the field or the message rendered under it had left
/// on the shared instance since. That is an empty margin, so the width the
/// gutter had reserved collapsed and the block jumped left under the pointer.
Widget _actionForNode(
  BlockComponentContext blockContext,
  BlockComponentActionState state,
) =>
    _scopeOf[blockContext.node]?.actionBuilder(blockContext, state) ??
    const SizedBox.shrink();

Widget _actionTrailingForNode(
  BlockComponentContext blockContext,
  BlockComponentActionState state,
) =>
    _scopeOf[blockContext.node]?.actionTrailingBuilder(blockContext, state) ??
    const SizedBox.shrink();

/// One editor's copy of a block builder: it holds the dressing itself and hands
/// it to [builder] just before that builds, so what another editor left on the
/// shared instance never reaches this one's blocks.
class _ScopedBlockComponentBuilder extends BlockComponentBuilder {
  final BlockComponentBuilder builder;

  _ScopedBlockComponentBuilder(this.builder)
    : super(configuration: builder.configuration);

  @override
  BlockComponentValidate get validate => builder.validate;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    _scopeOf[blockComponentContext.node] = this;

    builder
      ..configuration = configuration
      ..showActions = showActions
      // Never this scope's own: the blocks call these back later, and the field
      // they read them from belongs to the shared instance (see
      // [_actionForNode]).
      ..actionBuilder = _actionForNode
      ..actionTrailingBuilder = _actionTrailingForNode;

    return builder.build(blockComponentContext);
  }
}

/// No air above the heading that opens the page: nothing stands over it.
EdgeInsets _headingMargin(Node node, EdgeInsets Function(int level) margin) {
  final insets = margin(node.attributes[HeadingBlockKeys.level] as int? ?? 1);

  return node.previous == null ? insets.copyWith(top: 0) : insets;
}

/// The blocks that wear [RichTextTheme.listItemPadding] instead of the shared
/// rhythm: a list's items sit flush under one another at the document's own
/// padding, so they alone take the one the theme names for them.
final Set<String> _listTypes = {
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
};

/// Whether a block is part of a table rather than of the page itself — a cell,
/// or the paragraph a cell holds.
///
/// What hangs off a block on the page has no place in a cell: the margin
/// affordances and the placeholder both stop at the table's border.
bool _inTable(Node node) =>
    node.type == TableCellBlockKeys.type ||
    node.parent?.type == TableCellBlockKeys.type;
