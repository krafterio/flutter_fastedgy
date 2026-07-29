/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:path/path.dart' show basename;

import 'image_menu.dart';

final _log = getLogger('rich_text_image_store');

/// Stores a document's images as attachments of the record that document
/// belongs to, marked as part of [field]'s text.
///
/// Generic on purpose: an attachment points at its record through a generic
/// reference, so nothing here knows what a flow is. A note, a message, anything
/// holding rich text gives its own model and field and gets the same behaviour.
///
/// [recordId] is read at each call rather than captured: a screen builds its
/// features once, while the record it shows may still be loading.
ImageStore inlineImageStore({
  required String model,
  required int? Function() recordId,
  required String field,
}) {
  return (File file) async {
    final id = recordId();

    if (id == null) {
      // Nothing to hang the file off yet. The picture stays in the text, and
      // the server stores it when the record is saved.
      return null;
    }

    try {
      final uploaded = await getService<StorageUploader>().uploadAttachments(
        {basename(file.path): file},
        meta: (Attachment(
          {},
        ).attachToRecord(model, id)..inlineOn(field)).toJson(),
      );

      return uploaded.singleOrNull?.id;
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to store an image of $model.$field',
        error,
        stackTrace,
      );

      return null;
    }
  };
}
