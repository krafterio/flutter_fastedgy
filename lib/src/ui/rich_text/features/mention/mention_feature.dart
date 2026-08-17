/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../../../rich_text/rich_text_feature.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart'
    show getService, hasService;

import 'mention_controller.dart';
import 'mention_markdown.dart';
import 'mention_menu.dart';
import 'mention_options.dart';
import 'mention_source.dart';
import 'mention_span.dart';

/// What is armed and what has been typed since, one per editor.
///
/// Held beside the [EditorState] rather than inside the feature: the feature is
/// const and shared by every editor of the app, while a hunt belongs to the one
/// document it was started in. The entry goes when the state does, and the hunt
/// itself ends on the transaction stream closing under it.
final _controllers = Expando<MentionController>('rich text mentions');

/// Nothing to mention — what an app that registered no source offers.
final _none = MentionSources();

/// Mentioning a record from the text: `@` a member, `#` a flow, and whatever
/// else the app registered in [MentionSources] at boot.
///
/// The trigger is typed at a word boundary, the suggestions are filtered by
/// what is typed after it — spaces included, a project being called "Refonte du
/// site" — and Enter writes the mention as a link to the record's address.
/// Escape leaves the text as it was typed.
///
/// Nothing here knows what a flow is: a source does, and a source is all it
/// takes to mention one more kind of thing.
class MentionFeature extends RichTextFeature {
  /// [sources] overrides the app's registry, for a document that should offer
  /// fewer than everything — or none at all. [options] is what this document
  /// tells the sources it does offer; the standard set says nothing, so every
  /// source reads its own defaults.
  ///
  /// A document wanting either takes the standard features less this one and
  /// adds its own — `standardRichTextFeatures.without` this feature, `.and` a
  /// configured one. Where that leaves it in the list no longer matters: its
  /// "/" entries are placed by [menuGroup].
  const MentionFeature({this.sources, this.options = MentionOptions.none});

  final MentionSources? sources;

  final MentionOptions options;

  /// The hunt going on in [editorState], armed or not.
  ///
  /// The options are handed over on every read: the controller lives as long as
  /// the editor state, which outlives the widget that may be handing it new
  /// ones.
  MentionController controllerOf(EditorState editorState) =>
      (_controllers[editorState] ??= MentionController(registry))
        ..options = options;

  /// What this editor may mention: what it was handed, or what the app
  /// registered.
  MentionSources get registry =>
      sources ??
      (hasService<MentionSources>() ? getService<MentionSources>() : _none);

  /// Declared whatever the sources are: a document holding mentions is opened
  /// by editors that offer none — a reply box, a read-only page — and they have
  /// to render what is already written.
  ///
  /// Listed *after* [LinkFeature]: both ride on `href`, and the last one to
  /// rebuild a run is the one that owns it.
  @override
  TextSpanDecoratorForAttribute? get textSpanDecorator =>
      mentionTextSpanDecorator;

  /// A mention is an inline object in the editor and an ordinary link on the
  /// wire — markdown has no inline objects, and the field is read by the agent.
  /// Under the blocks, always: a mention is not one, and a set composed with a
  /// feature added late would otherwise show that one under them.
  @override
  int get menuGroup => 1;

  @override
  Document beforeMarkdown(Document document) => mentionsAsLinks(document);

  @override
  Document afterMarkdown(Document document) => linksAsMentions(document);

  @override
  List<CharacterShortcutEvent> get characterShortcuts {
    final registry = this.registry;

    return registry.isEmpty
        ? const []
        : [
            for (final character in registry.armingCharacters)
              _armOn(character),
            _writeOnEnter,
          ];
  }

  @override
  List<CommandShortcutEvent> get commandShortcuts => registry.isEmpty
      ? const []
      : [_highlightPrevious, _highlightNext, _closeOnEscape];

  /// Enter writes the mention being picked, and nothing else — least of all
  /// sending the message it was being picked for.
  @override
  bool holdsEnter(EditorState editorState) =>
      !registry.isEmpty && controllerOf(editorState).isOpen;

  /// Keeps the editor's own typing out of a query being written.
  ///
  /// A query is ordinary text sitting in the block, and the editor reads that
  /// block as markdown as it is typed: `#` armed and then a space taken as a
  /// heading, which converts the block and *deletes the trigger* — the machine
  /// then finds nothing where it was armed and gives up. A hyphen, a chevron,
  /// a digit and a dot do the same, and a pair of asterisks inside a name
  /// would turn it bold.
  ///
  /// While a hunt is on, every one of those declines and the character simply
  /// lands in the text, which is all a query ever is. The feature's own
  /// shortcuts are not wrapped, so Enter still writes the mention.
  @override
  CharacterShortcutEvent guard(CharacterShortcutEvent event) {
    if (registry.isEmpty) {
      return event;
    }

    return CharacterShortcutEvent(
      key: '${event.key} - skipped while a mention is being written',
      character: event.character,
      regExp: event.regExp,
      handler: (editorState) async => controllerOf(editorState).isOpen
          ? false
          : await event.handler(editorState),
      handlerWithCharacter: event.handlerWithCharacter == null
          ? null
          : (editorState, character) async => controllerOf(editorState).isOpen
                ? false
                : await event.handlerWithCharacter!(editorState, character),
    );
  }

  /// One entry per source, ranked as the registry ranks them, each doing
  /// nothing but typing the trigger: the machine takes over from there, exactly
  /// as if it had been typed by hand.
  @override
  List<SelectionMenuItem> get menuItems => [
    for (final source in registry.ordered)
      SelectionMenuItem(
        getName: source.getLabel,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          icon: source.icon,
          isSelected: isSelected,
          style: style,
        ),
        keywords: [
          source.getLabel().toLowerCase(),
          source.model,
          source.trigger,
        ],
        handler: (editorState, _, _) => _arm(editorState, source),
      ),
  ];

  /// Types [source]'s trigger where the caret is and opens its list.
  Future<void> _arm(EditorState editorState, MentionSource source) async {
    final selection = editorState.selection;
    final node = selection == null
        ? null
        : editorState.getNodeAtPath(selection.end.path);

    if (selection == null || node == null || !selection.isCollapsed) {
      return;
    }

    await editorState.insertTextAtPosition(
      source.trigger,
      position: selection.start,
    );

    _openAt(
      node,
      editorState,
      source,
      selection.end.offset + source.trigger.length,
    );
  }

  /// Arms the machine at once, and shows its list a frame later: the list hangs
  /// from the caret, and there is no rect to hang it from until the frame
  /// carrying the trigger has been drawn.
  ///
  /// The block's own context, looked up in that frame rather than carried into
  /// it: the one that armed the trigger may well be gone by then.
  void _openAt(
    Node node,
    EditorState editorState,
    MentionSource source,
    int caret,
  ) {
    final controller = controllerOf(editorState);

    controller.open(editorState, source, node.path, caret);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.key.currentContext;

      if (context == null || !context.mounted || !controller.isOpen) {
        return;
      }

      controller.anchor = editorState.selectionRects().firstOrNull;
      showMentionMenu(context, controller, editorState);
    });
  }

  /// Arms whatever source [character] ends the trigger of, and lets it be an
  /// ordinary character when none does.
  CharacterShortcutEvent _armOn(String character) => CharacterShortcutEvent(
    key: 'mention on $character',
    character: character,
    handler: (editorState) async {
      final selection = editorState.selection;

      if (selection == null || !selection.isCollapsed) {
        return false;
      }

      final node = editorState.getNodeAtPath(selection.end.path);
      final delta = node?.delta;

      if (node == null || delta == null) {
        return false;
      }

      final caret = selection.end.offset;
      final text = delta.toPlainText();
      final source = controllerOf(
        editorState,
      ).sourceFor(character, text.substring(0, caret.clamp(0, text.length)));

      if (source == null) {
        return false;
      }

      await editorState.insertTextAtPosition(
        character,
        position: selection.start,
      );

      _openAt(node, editorState, source, caret + 1);

      return true;
    },
  );

  /// Enter writes the highlighted suggestion. With nothing to write it declines
  /// the key, which then splits the block as it always would.
  CharacterShortcutEvent get _writeOnEnter => CharacterShortcutEvent(
    key: 'mention write',
    character: '\n',
    handler: (editorState) => controllerOf(editorState).validate(),
  );

  CommandShortcutEvent get _highlightNext => CommandShortcutEvent(
    key: 'mention next',
    getDescription: () => 'Next suggestion',
    command: 'arrow down',
    handler: (editorState) =>
        _handledIf(controllerOf(editorState).moveHighlight(1)),
  );

  CommandShortcutEvent get _highlightPrevious => CommandShortcutEvent(
    key: 'mention previous',
    getDescription: () => 'Previous suggestion',
    command: 'arrow up',
    handler: (editorState) =>
        _handledIf(controllerOf(editorState).moveHighlight(-1)),
  );

  /// Escape gives up on the mention and leaves the text as typed. Listed before
  /// the package's own, which would otherwise drop the selection instead.
  CommandShortcutEvent get _closeOnEscape => CommandShortcutEvent(
    key: 'mention close',
    getDescription: () => 'Cancel the mention',
    command: 'escape',
    handler: (editorState) {
      final controller = controllerOf(editorState);

      if (!controller.isOpen) {
        return KeyEventResult.ignored;
      }

      controller.close();

      return KeyEventResult.handled;
    },
  );

  static KeyEventResult _handledIf(bool handled) =>
      handled ? KeyEventResult.handled : KeyEventResult.ignored;
}
