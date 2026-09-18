/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';

/// What a screen reads off any holder, a record or a collection alike.
abstract interface class ApiHolder implements Listenable {
  bool get isLoading;

  /// Whether a read has been asked at least once.
  bool get isLoaded;

  Object? get error;

  Future<bool> reload();
}

/// Several holders read by one screen, seen as one: loading while any of them
/// is, loaded once all of them are, failed on the first error.
///
/// It listens to the holders without owning them: whoever created them
/// disposes them.
class ApiHolders extends ChangeNotifier implements ApiHolder {
  ApiHolders(this.holders) {
    for (final holder in holders) {
      holder.addListener(notifyListeners);
    }
  }

  final List<ApiHolder> holders;

  @override
  bool get isLoading => holders.any((holder) => holder.isLoading);

  @override
  bool get isLoaded => holders.every((holder) => holder.isLoaded);

  @override
  Object? get error {
    for (final holder in holders) {
      if (holder.error != null) return holder.error;
    }

    return null;
  }

  @override
  Future<bool> reload() async {
    final results = await Future.wait(holders.map((holder) => holder.reload()));

    return results.every((ok) => ok);
  }

  @override
  void dispose() {
    for (final holder in holders) {
      holder.removeListener(notifyListeners);
    }

    super.dispose();
  }
}
