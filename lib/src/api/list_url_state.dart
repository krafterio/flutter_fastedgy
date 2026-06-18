/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Persists a list screen's state (filter, search, page, scroll, …) in the
/// router query params and restores it on (re)entry — the URL is the store, so
/// it survives navigation, browser back/forward, refresh and deep links without
/// any cache or holder. Pairs with [ApiCollection] (see loadThroughPage).
///
/// The screen owns the mapping between its state and the params; this mixin only
/// reads the current params and writes them back (debounced, via replace so it
/// does not pollute history).
mixin ListUrlState<W extends StatefulWidget> on State<W> {
  Timer? _urlDebounce;

  /// Current router query parameters for this screen.
  Map<String, String> get urlParams => GoRouterState.of(context).uri.queryParameters;

  /// True when the screen was (re)entered with query state already present
  /// (router back/forward, deep link, restore) → skip entry animations.
  bool get isUrlRestore => urlParams.isNotEmpty;

  /// Merges [params] into the current URL query (null/empty values remove the
  /// key) and replaces the location, debounced.
  void writeUrl(Map<String, String?> params, {Duration debounce = const Duration(milliseconds: 350)}) {
    _urlDebounce?.cancel();
    _urlDebounce = Timer(debounce, () {
      if (!mounted) return;
      final state = GoRouterState.of(context);
      final query = Map<String, String>.from(state.uri.queryParameters);
      params.forEach((key, value) {
        if (value == null || value.isEmpty) {
          query.remove(key);
        } else {
          query[key] = value;
        }
      });
      context.replace(Uri(path: state.uri.path, queryParameters: query.isEmpty ? null : query).toString());
    });
  }

  @override
  void dispose() {
    _urlDebounce?.cancel();
    super.dispose();
  }
}
