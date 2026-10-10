/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The page size of a list, the port of `usePageSize`: the size the URL says
/// ([fromUrl]), else the one kept under [storageKey], else [defaultSize],
/// else the first of [available], each one only when [available] offers it.
/// A size set is kept under [storageKey].
///
/// The kept size is read from the device: [ready] completes once it is
/// known, which the first read of a list waits for.
class PageSize extends ValueNotifier<int> {
  PageSize(
    this.available, {
    String? fromUrl,
    int defaultSize = 50,
    this.storageKey,
  }) : super(
         _offered(available, int.tryParse(fromUrl ?? '')) ??
             _offered(available, defaultSize) ??
             available.first,
       ) {
    final fromLink = _offered(available, int.tryParse(fromUrl ?? ''));

    ready = fromLink != null || storageKey == null
        ? Future.value()
        : _readKept();

    if (storageKey != null) {
      addListener(_keep);
    }
  }

  final List<int> available;
  final String? storageKey;

  late final Future<void> ready;

  static int? _offered(List<int> available, int? size) =>
      size != null && available.contains(size) ? size : null;

  Future<void> _readKept() async {
    try {
      final kept = _offered(
        available,
        (await SharedPreferences.getInstance()).getInt(storageKey!),
      );

      if (kept != null) {
        value = kept;
      }
    } catch (_) {
      // Nothing kept to read: the default size stays.
    }
  }

  Future<void> _keep() async {
    try {
      await (await SharedPreferences.getInstance()).setInt(storageKey!, value);
    } catch (_) {
      // Nowhere to keep it: the size holds for the session.
    }
  }
}
