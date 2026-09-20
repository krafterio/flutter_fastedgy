/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
import 'local_image_store.dart';
import 'local_sequence.dart';
import 'local_store.dart';
import 'pending_upload_store.dart';
import 'replica.dart';

/// Empties every registered offline store: the record mirror, the resource
/// cache, the buffered writes and their files, the mirrored images.
///
/// What the logout purge does, for an application that has to forget its local
/// data at another moment too — a tenant switch, a scope the mirror is not
/// partitioned for yet.
Future<void> purgeOfflineStores() => Future.wait([
  if (hasService<Replica>()) getService<Replica>().clearAll(),
  if (hasService<LocalImageStore>()) getService<LocalImageStore>().clear(),
  if (hasService<PendingUploadStore>())
    getService<PendingUploadStore>().clearAll(),
  if (hasService<LocalSequence>()) getService<LocalSequence>().clearAll(),
  if (hasService<LocalStore>()) getService<LocalStore>().clearAll(),
]);
