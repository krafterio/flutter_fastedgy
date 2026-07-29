/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:typed_data';

/// How an image block points at its picture.
///
/// Three shapes reach a document. An attachment is what an image settles as,
/// the file living beside the record. A `data:` URI is what a paste carries and
/// what an offline insert leaves behind, until a save turns it into an
/// attachment. Anything else is a plain address, left as it was written.
const attachmentScheme = 'attachment:';

/// The attachment an image is stored as, or null when it points elsewhere.
int? attachmentIdOf(String? url) {
  if (url == null || !url.startsWith(attachmentScheme)) {
    return null;
  }

  return int.tryParse(url.substring(attachmentScheme.length));
}

String attachmentImageUrl(int id) => '$attachmentScheme$id';

/// The bytes of a `data:` image, or null when [url] is not one — or is one we
/// cannot read.
Uint8List? inlineImageBytes(String? url) {
  if (url == null || !url.startsWith('data:')) {
    return null;
  }

  final comma = url.indexOf(',');

  if (comma < 0 || !url.substring(0, comma).contains(';base64')) {
    return null;
  }

  try {
    return base64Decode(url.substring(comma + 1));
  } catch (_) {
    return null;
  }
}
