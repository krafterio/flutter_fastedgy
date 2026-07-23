/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Provides values for the offline context (`{param}` placeholders of
/// resource base paths), re-read on every call so they follow live app state
/// (selected tenant, …).
abstract interface class OfflineContextParamsResolver {
  Map<String, Object?> resolve();
}

/// Registry of the offline context: replica scoping and buffered writes
/// derive from the values the registered [OfflineContextParamsResolver]s provide
/// for the params a base path declares — the path itself is never resolved
/// here, and no param name is hardcoded.
class OfflineContextParams {
  static final _paramPattern = RegExp(r'\{([A-Za-z0-9_]+)\}');

  final List<OfflineContextParamsResolver> _resolvers = [];

  void register(OfflineContextParamsResolver resolver) =>
      _resolvers.add(resolver);

  void unregister(OfflineContextParamsResolver resolver) =>
      _resolvers.remove(resolver);

  static List<String> paramsOf(String path) =>
      _paramPattern.allMatches(path).map((match) => match.group(1)!).toList();

  /// Merged values, a later registration overriding an earlier one.
  Map<String, Object?> resolve() => {
    for (final resolver in _resolvers) ...resolver.resolve(),
  };

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
  Map<String, String> contextFor(String path) {
    final params = paramsOf(path);

    if (params.isEmpty) {
      return const {};
    }

    final values = resolve();
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

  /// Replica scope of a resource at [path]: its context values joined by
  /// `/`; '' for a global (param-less or unresolved) resource.
  String scopeOf(String path) => contextFor(path).values.join('/');
}
