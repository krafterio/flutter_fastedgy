/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../../../../api/sync_image_field.dart';
import 'image_component.dart';
import 'image_source.dart';

/// The attachments a document references, as storage paths.
///
/// A picture in a document is an attachment of the record, and the text points
/// at it by `attachment:<id>`, with the size it is drawn at riding along. The
/// file itself is read from the attachment path, at one fixed width.
Set<String> documentImagePaths(String markdown) => {
  for (final match in RegExp('$attachmentScheme(\\d+)').allMatches(markdown))
    if (int.tryParse(match.group(1)!) case final int id)
      attachmentDownloadPath(id),
};

/// Mirrors the pictures a rich text [field] holds, at the width they are read
/// with ([imageDownloadWidth]): a mirrored note keeps its images offline, not
/// only its text.
SyncImageField richTextImages(String field) => SyncImageField(
  field,
  paths: documentImagePaths,
  variants: const [ImageVariant(width: imageDownloadWidth)],
);
