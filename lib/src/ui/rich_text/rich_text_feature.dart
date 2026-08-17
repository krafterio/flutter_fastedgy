/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

import 'rich_text_action.dart';

import 'package:flutter/painting.dart' show TextSpan;

/// One content feature of a [DocumentEditor]: everything a kind of block needs,
/// declared in one place — how it renders, how it is typed and inserted, and
/// how it is written to and read back from markdown.
///
/// Adding a feature is writing one of these and listing it in a
/// [RichTextFeatures] registry; nothing in the editor has to be touched.
abstract class RichTextFeature {
  const RichTextFeature();

  /// Blocks this feature renders, keyed by node type. A type the package
  /// already knows is overridden rather than added — that is how a standard
  /// block gets our own look.
  Map<String, BlockComponentBuilder> get builders => const {};

  /// What it adds to the "/" menu.
  List<SelectionMenuItem> get menuItems => const [];

  /// Where those entries sit among the other features', lowest first.
  ///
  /// A block is something the document holds, and they come in the order the
  /// set was composed in. A mention points at something outside it, and belongs
  /// under them however the set was composed — an application binding a feature
  /// late (a picture that needs the record to store it against) appends it, and
  /// it would otherwise land past the mentions.
  int get menuGroup => 0;

  /// Entries of the package's own "/" menu this feature stands in for, by the
  /// label the package ships ('Image'). Without this the two would sit side by
  /// side, one of them opening the block we replaced.
  Set<String> get replacesMenuItems => const {};

  /// What it adds to the toolbar floating over a selection — an inline format
  /// rather than a block of its own.
  List<ToolbarItem> get toolbarItems => const [];

  /// What it adds to the strip of formatting actions.
  List<RichTextAction> get actions => const [];

  /// How the rendered text of its attribute looks and answers to the pointer.
  ///
  /// The editor takes a single one; [RichTextFeatures] chains what the features
  /// declare, each handed what the one before it made. A decorator that has
  /// nothing to say about a run returns that untouched.
  TextSpanDecoratorForAttribute? get textSpanDecorator => null;

  /// Typing triggers of its own (a markdown shorthand, a character that opens
  /// the block).
  List<CharacterShortcutEvent> get characterShortcuts => const [];

  /// Key bindings of its own. They are offered before the package's, so a
  /// feature can take over a key while its block holds the cursor.
  List<CommandShortcutEvent> get commandShortcuts => const [];

  /// Whether Enter belongs to this feature right now — a menu it opened on the
  /// caret, a block that keeps its own line breaks.
  ///
  /// Only an editor that binds Enter to something else asks (see
  /// [RichTextEditor.onSubmit]): a composer sends on Enter, and must not send
  /// the message somebody was picking a mention for.
  bool holdsEnter(EditorState editorState) => false;

  /// Wraps every *other* character shortcut, this feature's own excepted.
  ///
  /// This is what lets a block swallow the editor's usual typing behaviour
  /// while the cursor sits in it — inside a code block, Enter and the markdown
  /// triggers must insert plain characters instead of splitting or formatting.
  CharacterShortcutEvent guard(CharacterShortcutEvent event) => event;

  /// Writes its blocks to markdown. JSON needs no counterpart: it stores the
  /// node tree as it stands, so it carries any block without being taught one.
  List<NodeParser> get markdownEncoders => const [];

  /// Reads them back. Without this the package's decoder silently drops the
  /// block, and what was saved comes back as nothing — the encoder alone is
  /// only half a round trip.
  List<CustomMarkdownParser> get markdownDecoders => const [];

  /// Spellings the parser is taught to read *inside* a block, where
  /// [markdownDecoders] only ever sees whole ones.
  ///
  /// Offered before the package's own, so a syntax declared here is tried first
  /// wherever the two could both match.
  List<md.InlineSyntax> get markdownInlineSyntaxes => const [];

  /// A last pass over the whole document before it is written to markdown, for
  /// what a node parser cannot reach — dropping what the format already says
  /// implicitly, or writing an inline object as the plain markup that stands
  /// for it.
  Document beforeMarkdown(Document document) => document;

  /// The mirror of [beforeMarkdown], run over what was just read back.
  ///
  /// Markdown has no inline objects: what a feature writes as ordinary markup
  /// comes home as ordinary markup, and this is where it becomes itself again.
  /// The two together are what has to round-trip, not either one alone.
  Document afterMarkdown(Document document) => document;
}

/// The content features a document offers, in one list.
///
/// A registry only ever *adds* to what the package already does: its standard
/// blocks stay rendered, and its markdown parsers stay in the round trip behind
/// ours. Leaving a feature out therefore removes what it contributes, not what
/// the package contributes on its own.
///
/// Order matters where two features collide: the last one listed wins a node
/// type, and every guard wraps the shortcuts of the others.
class RichTextFeatures {
  final List<RichTextFeature> features;

  const RichTextFeatures(this.features);

  /// The same set less the features of type [T] — `without<CodeBlockFeature>()`
  /// on a composer that should hold prose and nothing else.
  RichTextFeatures without<T extends RichTextFeature>() => RichTextFeatures([
    for (final feature in features)
      if (feature is! T) feature,
  ]);

  /// The same set less the features of these kinds — [without] said at runtime,
  /// for a caller naming them in a list rather than in a type argument.
  RichTextFeatures withoutAll(Set<Type> kinds) => RichTextFeatures([
    for (final feature in features)
      if (!kinds.contains(feature.runtimeType)) feature,
  ]);

  /// The same set plus [added], which win any node type they share with it.
  RichTextFeatures and(List<RichTextFeature> added) =>
      RichTextFeatures([...features, ...added]);

  Map<String, BlockComponentBuilder> get builders => {
    for (final feature in features) ...feature.builders,
  };

  List<SelectionMenuItem> get menuItems => [
    for (final feature in _byMenuGroup) ...feature.menuItems,
  ];

  /// The features in the order their "/" entries are offered in: by group, and
  /// within one by the order they were declared in.
  ///
  /// Sorted on the position rather than with `sort`, which Dart does not
  /// promise to keep stable — two features of the same group could then swap
  /// places from one call to the next.
  List<RichTextFeature> get _byMenuGroup {
    final ordered = features.indexed.toList()
      ..sort((a, b) {
        final byGroup = a.$2.menuGroup.compareTo(b.$2.menuGroup);

        return byGroup != 0 ? byGroup : a.$1.compareTo(b.$1);
      });

    return [for (final (_, feature) in ordered) feature];
  }

  Set<String> get replacedMenuItems => {
    for (final feature in features) ...feature.replacesMenuItems,
  };

  List<RichTextAction> get actions => [
    for (final feature in features) ...feature.actions,
  ];

  List<ToolbarItem> get toolbarItems => [
    for (final feature in features) ...feature.toolbarItems,
  ];

  /// Every feature's decorator, in order, each handed what the one before it
  /// made — so two features can dress the same attribute for different values
  /// of it, a link and a mention both riding on `href`. The last one to rebuild
  /// a run is therefore the one that wins it.
  TextSpanDecoratorForAttribute? get textSpanDecorator {
    final decorators = [
      for (final feature in features) ?feature.textSpanDecorator,
    ];

    if (decorators.isEmpty) {
      return null;
    }

    return (context, node, index, text, before, after) {
      var decorated = before;

      for (final decorate in decorators) {
        final span = decorate(context, node, index, text, decorated, after);

        // Being chained, each has to hand the next something it can decorate in
        // turn. Anything else is a run nobody after it gets to see.
        if (span is! TextSpan) {
          return span;
        }

        decorated = span;
      }

      return decorated;
    };
  }

  List<CharacterShortcutEvent> get characterShortcuts => [
    for (final feature in features) ...feature.characterShortcuts,
  ];

  List<CommandShortcutEvent> get commandShortcuts => [
    for (final feature in features) ...feature.commandShortcuts,
  ];

  List<NodeParser> get markdownEncoders => [
    for (final feature in features) ...feature.markdownEncoders,
  ];

  List<CustomMarkdownParser> get markdownDecoders => [
    for (final feature in features) ...feature.markdownDecoders,
  ];

  List<md.InlineSyntax> get markdownInlineSyntaxes => [
    for (final feature in features) ...feature.markdownInlineSyntaxes,
  ];

  Document beforeMarkdown(Document document) => features.fold(
    document,
    (shaped, feature) => feature.beforeMarkdown(shaped),
  );

  /// Undone in reverse, so a document goes back through the passes the way it
  /// came out of them.
  Document afterMarkdown(Document document) => features.reversed.fold(
    document,
    (shaped, feature) => feature.afterMarkdown(shaped),
  );

  /// Whether any feature is holding Enter — one is enough for the key to stay
  /// where it usually goes.
  bool holdsEnter(EditorState editorState) =>
      features.any((feature) => feature.holdsEnter(editorState));

  /// Puts [event] behind every feature's guard.
  CharacterShortcutEvent guard(CharacterShortcutEvent event) =>
      features.fold(event, (guarded, feature) => feature.guard(guarded));
}
