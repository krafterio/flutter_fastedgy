/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show Zone, runZoned;

/// Provides values for the offline context (`{param}` placeholders of
/// resource base paths), re-read on every call so they follow live app state
/// (selected tenant, …).
abstract interface class OfflineContextParamsResolver {
  /// Values a path is substituted with — what the server sees in the URL.
  Map<String, Object?> resolve();
}

/// Implemented alongside [OfflineContextParamsResolver] by a resolver whose
/// local data is scoped by something other than what its paths carry.
///
/// A URL wants whatever the route matches on (a slug), while a scope wants
/// something that outlives a rename (an id): renaming a workspace would
/// otherwise strand every row mirrored under its former slug. A resolver that
/// does not implement this is scoped by its [resolve] values, as before.
abstract interface class OfflineScopeParamsResolver
    implements OfflineContextParamsResolver {
  Map<String, Object?> resolveScope();
}

/// Registry of the offline context: replica scoping and buffered writes
/// derive from the values the registered [OfflineContextParamsResolver]s provide
/// for the params a base path declares — the path itself is never resolved
/// here, and no param name is hardcoded.
class OfflineContextParams {
  static final _paramPattern = RegExp(r'\{([A-Za-z0-9_]+)\}');
  static final _zoneKey = Object();

  final List<OfflineContextParamsResolver> _resolvers = [];
  final List<OfflineContextParamsResolver> _globals = [];

  /// Registers [resolver]. A [global] one also scopes the resources whose path
  /// declares no param, for an API that carries its tenant in the session
  /// rather than in the URL.
  void register(OfflineContextParamsResolver resolver, {bool global = false}) {
    _resolvers.add(resolver);

    if (global) {
      _globals.add(resolver);
    }
  }

  void unregister(OfflineContextParamsResolver resolver) {
    _resolvers.remove(resolver);
    _globals.remove(resolver);
  }

  static List<String> paramsOf(String path) =>
      _paramPattern.allMatches(path).map((match) => match.group(1)!).toList();

  /// Runs [body] in the context [values] give, over whatever the registered
  /// resolvers say: every call, sync or buffered write it starts substitutes,
  /// captures and mirrors under them, while the rest of the app stays where it
  /// is. [scope] is what they are mirrored under, [values] when none is given,
  /// as for a resolver without a scope. A nested call adds to the outer one.
  static R within<R>(
    Map<String, Object?> values,
    R Function() body, {
    Map<String, Object?>? scope,
  }) {
    final outer = _within;

    return runZoned(
      body,
      zoneValues: {
        _zoneKey: (
          values: {...?outer?.values, ...values},
          scope: {...?outer?.scope, ...(scope ?? values)},
        ),
      },
    );
  }

  /// What [within] gives the code running now, null outside of it.
  static Map<String, Object?>? get withinValues => _within?.values;

  static ({Map<String, Object?> values, Map<String, Object?> scope})?
  get _within =>
      Zone.current[_zoneKey]
          as ({Map<String, Object?> values, Map<String, Object?> scope})?;

  /// Merged values, a later registration overriding an earlier one, and
  /// [within] overriding them all.
  Map<String, Object?> resolve() => {
    for (final resolver in _resolvers) ...resolver.resolve(),
    ...?_within?.values,
  };

  /// Merged scope values: what a resolver declares through
  /// [OfflineScopeParamsResolver], falling back to what it substitutes.
  Map<String, Object?> resolveScope() {
    final values = <String, Object?>{};

    for (final resolver in _resolvers) {
      values.addAll(
        resolver is OfflineScopeParamsResolver
            ? resolver.resolveScope()
            : resolver.resolve(),
      );
    }

    return {...values, ...?_within?.scope};
  }

  /// [path] substituted from an explicit [context] — how a buffered offline
  /// write replays under the context it was captured in, not the current
  /// one. A param without value keeps its placeholder.
  static String substituteWith(String path, Map<String, Object?> context) {
    if (!path.contains('{')) {
      return path;
    }

    return path.replaceAllMapped(_paramPattern, (match) {
      final value = context[match.group(1)];

      return value == null || '$value'.isEmpty ? match.group(0)! : '$value';
    });
  }

  /// Offline context of a resource at [path]: the current values of the
  /// params its path declares. Empty for a param-less path or while any
  /// param is unresolved.
  ///
  /// These are the substitution values: a buffered write keeps them to replay
  /// its path later, so they must stay what the server matches on.
  Map<String, String> contextFor(String path) => _valuesFor(path, resolve());

  /// Replica scope of a resource at [path]: its scope values joined by `/`.
  ///
  /// A path without param takes the scope of the resolvers registered as
  /// global, and '' when there is none — an unscoped mirror, as before.
  String scopeOf(String path) {
    if (paramsOf(path).isEmpty) {
      return _globalScope();
    }

    return declaredScopeOf(path);
  }

  /// Scope of what a resource at [path] caches outside the replica: the scope
  /// values of the params its path declares, joined by `/`, and '' for a path
  /// that declares none. Unlike [scopeOf], never the global scope, so a cache
  /// the app keys by path alone keeps its keys.
  String declaredScopeOf(String path) =>
      _valuesFor(path, resolveScope()).values.join('/');

  String _globalScope() {
    final values = <String, Object?>{};

    for (final resolver in _globals) {
      values.addAll(
        resolver is OfflineScopeParamsResolver
            ? resolver.resolveScope()
            : resolver.resolve(),
      );
    }

    // [within] moves what the global resolvers scope, and adds nothing to it:
    // a path declaring no param is no more scoped inside it than outside.
    final overrides = _within?.scope ?? const {};

    for (final key in values.keys.toList()) {
      if (overrides.containsKey(key)) {
        values[key] = overrides[key];
      }
    }

    return values.values
        .where((value) => value != null && '$value'.isNotEmpty)
        .map((value) => '$value')
        .join('/');
  }

  Map<String, String> _valuesFor(String path, Map<String, Object?> values) {
    final params = paramsOf(path);

    if (params.isEmpty) {
      return const {};
    }

    final context = <String, String>{};

    for (final param in params) {
      final value = values[param];

      if (value == null || '$value'.isEmpty) {
        return const {};
      }

      context[param] = '$value';
    }

    return context;
  }
}
