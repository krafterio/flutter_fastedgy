/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart'
    show getService, hasService;

/// Where a mention points.
///
/// The record's address, never the view's: a record moved elsewhere is the same
/// record, and the mention still names it. The module carries it, compares it
/// and writes it into markdown; what it *means* and what it *opens* belong to
/// the application.
@immutable
class MentionAddress {
  /// Model name as the API names it — `flow`, `project`, `user`.
  final String model;

  final int id;

  /// What is stored in the document and written into markdown.
  final Uri uri;

  const MentionAddress({
    required this.model,
    required this.id,
    required this.uri,
  });

  @override
  bool operator ==(Object other) =>
      other is MentionAddress &&
      other.model == model &&
      other.id == id &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(model, id, uri);

  @override
  String toString() => uri.toString();
}

/// How an address is written into a document and read back out of one.
///
/// A **service**, not a theme: the round trip runs in the markdown parsers and
/// in the JSON decoder, neither of which has a context to read from. Register
/// one in the container and the module writes addresses an application can
/// resolve; register none and mentions still draw, but as plain text.
abstract class MentionAddressing {
  const MentionAddressing();

  /// The address of [model] `#`[id], in whatever shape the application routes.
  ///
  /// Null where it cannot be written yet — an address scoped to a workspace,
  /// asked for before one is chosen. The mention is dropped rather than stored
  /// pointing nowhere.
  Uri? encode({required String model, required int id});

  /// Null for a URI this application does not recognise — a link to the web, or
  /// an address written by a different product.
  MentionAddress? decode(Uri uri);
}

/// The registered addressing, or null where an application registered none.
MentionAddressing? get mentionAddressing =>
    hasService<MentionAddressing>() ? getService<MentionAddressing>() : null;

/// Opens what a mention points at.
///
/// A service for the same reason, and null where nothing can be opened — a
/// member is somebody, not a screen.
abstract class RecordOpener {
  const RecordOpener();

  Future<void> open(MentionAddress address);
}

RecordOpener? get recordOpener =>
    hasService<RecordOpener>() ? getService<RecordOpener>() : null;
