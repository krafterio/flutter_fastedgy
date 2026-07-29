/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'mention_options.dart';
import 'mention_preview.dart';
import 'mention_span.dart';

/// How a candidate's label reads in the menu.
enum MentionLabelShape {
  /// A name: what the row is about, and what it is read by.
  title,

  /// A code standing for the record — a flow's `KAS-42`. Drawn the way a
  /// reference is drawn everywhere else in the app rather than as a title, with
  /// the record's name taking the line under it.
  reference,
}

/// One thing that can be mentioned: a row of the suggestion menu, and the
/// record the mention will point at.
class MentionCandidate {
  /// Server id of the record, which is what the mention stores.
  final int id;

  /// What is written into the text after the trigger — a display name, a flow
  /// reference. Never the id: the text is read by people and by the agent.
  final String label;

  /// Second line of the menu row: what tells two records of the same name
  /// apart. Null leaves the row on one line.
  final String? subtitle;

  /// Avatar or icon shown ahead of the label.
  final Widget? leading;

  /// How [label] reads. A source whose label is a code says so, and the row
  /// draws the two lines the other way round — the name to read, the code to
  /// recognise.
  final MentionLabelShape labelShape;

  const MentionCandidate({
    required this.id,
    required this.label,
    this.subtitle,
    this.leading,
    this.labelShape = MentionLabelShape.title,
  });
}

/// A kind of mention: what opens it, what it offers, and what record it writes.
///
/// One source per model. Nothing about the editor is in here, and nothing about
/// a particular model is anywhere else — adding `%` for projects is adding one
/// of these to the feature's list.
class MentionSource {
  /// What arms the menu, typed at a word boundary. More than one character is
  /// allowed: a single one that reads as punctuation elsewhere (`:`) collides
  /// with what people type, which is why Odoo moved its canned responses from
  /// `:` to `::`.
  final String trigger;

  /// Model name as the API names it (`flow`, `project`, `note`, `user`) — what
  /// goes into the record address the mention stores.
  final String model;

  /// What the "/" menu calls it.
  ///
  /// Read at each display, never once at registration: the sources are declared
  /// while the app boots, and `t()` called then would answer before the
  /// translations are loaded and hand back the English key for good.
  final String Function() getLabel;

  /// Its "/" menu icon.
  final IconData icon;

  /// Where it sits among the others: highest first, ties keeping the order they
  /// were registered in. Spaced by a hundred in the standard set, so one more
  /// source can slot between two without renumbering them.
  ///
  /// It never decides which trigger arms — a longer trigger always outranks a
  /// shorter one it ends with, or `::` could never win over `:`.
  final int priority;

  /// What the trigger offers for [query], already in the order to show them.
  ///
  /// Called on every keystroke behind a debounce, and reached through the API,
  /// so a workspace working offline answers from its mirror.
  ///
  /// [options] is whatever the document said; a source reading none offers the
  /// same suggestions everywhere.
  final Future<List<MentionCandidate>> Function(
    String query,
    MentionOptions options,
  )
  search;

  /// What to do the moment the mention is written, for effects that belong to
  /// this device. Notifying anybody does not: a mention typed into a draft that
  /// is never saved must not reach a soul, so that is the server's call on the
  /// text it persists.
  final Future<void> Function(MentionCandidate candidate)? onMention;

  /// What a mention of this kind shows when it is clicked; null when the record
  /// could not be read, and left out entirely when there is nothing to show.
  final Future<MentionPreview?> Function(int id)? preview;

  /// The shape [preview] settles on, drawn while it is being read.
  ///
  /// Declared beside the card it stands in for, so the two cannot drift: a
  /// skeleton of the wrong shape trades a blank card for a jump.
  final MentionPreviewShape previewShape;

  /// Whether the record has a view of its own.
  ///
  /// False where it has none — a member is somebody, not a screen — and the
  /// card then offers nothing to open. Where it is true, opening goes through
  /// the registered [RecordOpener]: resolving a record's address into a view's
  /// is the application's routing, not the module's.
  final bool openable;

  const MentionSource({
    required this.trigger,
    required this.model,
    required this.getLabel,
    required this.icon,
    required this.search,
    this.onMention,
    this.preview,
    this.previewShape = MentionPreviewShape.none,
    this.openable = false,
    this.priority = 0,
  });

  /// Last character of the trigger — the keystroke that can arm this source.
  String get armingCharacter => trigger.substring(trigger.length - 1);
}

/// What this app can mention, registered at boot.
///
/// A service rather than a value the editor is handed: a screen shows a
/// [RichTextEditor] and nothing else, so what a document may mention is the
/// app's to declare once — `main.dart` registers a source per model, and every
/// editor of every screen offers them without naming one.
///
/// Left unregistered — a test, a package used on its own — the editor simply
/// arms nothing.
class MentionSources {
  MentionSources([Iterable<MentionSource> sources = const []])
    : _sources = [...sources] {
    keepMentionsWhole();
  }

  final List<MentionSource> _sources;

  void register(MentionSource source) => _sources.add(source);

  void registerAll(Iterable<MentionSource> sources) => _sources.addAll(sources);

  List<MentionSource> get all => List.unmodifiable(_sources);

  bool get isEmpty => _sources.isEmpty;

  /// The distinct keystrokes that can arm something.
  Set<String> get armingCharacters => {
    for (final source in _sources) source.armingCharacter,
  };

  /// Who knows about [model] — what a mention already written asks for when it
  /// is clicked, having only the address to go on.
  MentionSource? forModel(String model) =>
      _sources.where((source) => source.model == model).firstOrNull;

  /// What the "/" menu shows, and in what order.
  List<MentionSource> get ordered =>
      _sorted((a, b) => b.priority.compareTo(a.priority));

  /// What a keystroke is matched against.
  ///
  /// Longest trigger first, whatever the priorities: `::` has to be tried
  /// before the `:` it ends with, or it could never arm at all.
  List<MentionSource> get armingOrder => _sorted((a, b) {
    final length = b.trigger.length.compareTo(a.trigger.length);

    return length != 0 ? length : b.priority.compareTo(a.priority);
  });

  /// Sorted stably, so equal ranks keep the order they were registered in.
  List<MentionSource> _sorted(
    int Function(MentionSource a, MentionSource b) rank,
  ) {
    final ranked = [..._sources.indexed];

    ranked.sort((a, b) {
      final order = rank(a.$2, b.$2);

      return order != 0 ? order : a.$1.compareTo(b.$1);
    });

    return [for (final (_, source) in ranked) source];
  }
}
