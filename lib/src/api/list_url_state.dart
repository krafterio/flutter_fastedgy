/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Persists a list screen's state (filter, search, page, scroll, …) in the
/// router query params and restores it on (re)entry — the URL is the store, so
/// it survives navigation, browser back/forward, refresh and deep links without
/// any cache or holder. Pairs with [ApiCollection] (see loadThroughPage).
///
/// The screen implements [applyUrlState] to read the params into its state and
/// collection, and calls [writeUrl] when its state changes. The mixin handles
/// the lifecycle: it calls [applyUrlState] once on first build and again only
/// when the URL changes from the outside (router back/forward, deep link) —
/// never for the screen's own [writeUrl], and never for unrelated dependency
/// changes (keyboard, theme…).
mixin ListUrlState<W extends StatefulWidget> on State<W> {
  Timer? _urlDebounce;
  Map<String, String>? _lastParams;
  bool _urlInitDone = false;

  /// Current router query parameters for this screen.
  Map<String, String> get urlParams =>
      GoRouterState.of(context).uri.queryParameters;

  /// True when the screen is (re)entered with query state already present
  /// (router back/forward, deep link, restore) → skip entry animations.
  bool get isUrlRestore => urlParams.isNotEmpty;

  /// Apply the URL [params] to the screen state / collection. Called with
  /// [initial] true on first build, then false on each external URL change.
  void applyUrlState(Map<String, String> params, {required bool initial});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final params = urlParams;
    if (!_urlInitDone) {
      _urlInitDone = true;
      _lastParams = params;
      applyUrlState(params, initial: true);
    } else if (!mapEquals(params, _lastParams)) {
      _lastParams = params;
      applyUrlState(params, initial: false);
    }
  }

  /// Merges [params] into the current URL query (null/empty values remove the
  /// key) and replaces the location, debounced. The write is not echoed back to
  /// [applyUrlState].
  void writeUrl(
    Map<String, String?> params, {
    Duration debounce = const Duration(milliseconds: 350),
  }) {
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
      _lastParams = query;
      context.replace(
        Uri(
          path: state.uri.path,
          queryParameters: query.isEmpty ? null : query,
        ).toString(),
      );
    });
  }

  @override
  void dispose() {
    _urlDebounce?.cancel();
    super.dispose();
  }
}
