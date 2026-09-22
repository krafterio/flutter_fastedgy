/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../container/container.dart';
import '../fetcher/client.dart';
import '../logging/logger.dart';
import '../metadata/metadata_provider.dart';

/// What the server holds for one replicated model, as the sync state route
/// answers it (`GET /dataset/sync-state`).
class SyncModelState {
  final String model;

  /// `full` or `partial`, as the model declares it.
  final String mode;

  /// How many records the caller can read.
  final int count;

  /// `updated_at` of the freshest one, null when the model holds nothing.
  final String? updatedAt;

  const SyncModelState({
    required this.model,
    required this.mode,
    required this.count,
    this.updatedAt,
  });

  factory SyncModelState.fromJson(Map<String, dynamic> json) => SyncModelState(
    model: '${json['model']}',
    mode: '${json['mode']}',
    count: (json['count'] as num?)?.toInt() ?? 0,
    updatedAt: json['updated_at'] as String?,
  );
}

/// Asks the server, in one request, how much each replicated model holds.
///
/// Mirroring a model means walking its manifest, a request per page, even when
/// nothing moved. This answers the same question for every model at once, so a
/// sync whose own numbers match can be skipped entirely. Nothing is stored per
/// device on either side: the client keeps its own cursor in the replica.
class SyncStateProbe {
  final Fetcher? _fetcherOverride;

  /// Path prefix of the route, when the app does not go through the metadata
  /// provider's own (a console, an agent API).
  final String? prefix;

  /// How long one answer serves every model it covered.
  ///
  /// A round of syncs asks once for all of them, then each model asks for
  /// itself: without this the saved requests would come straight back.
  final Duration freshness;

  final _logger = getLogger('SyncStateProbe');

  /// The last answer of each scope: two workspaces synced one after the other
  /// never read each other's states.
  final _answers =
      <
        String,
        ({
          Map<String, SyncModelState> states,
          Set<String>? covered,
          DateTime at,
        })
      >{};

  SyncStateProbe({
    Fetcher? fetcher,
    this.prefix,
    this.freshness = const Duration(seconds: 30),
  }) : _fetcherOverride = fetcher;

  Fetcher get _fetcher => _fetcherOverride ?? getService<Fetcher>();

  /// The scope the metadata are read under, so a tenant-specific prefix
  /// (`/{workspace}`) reaches the same server as the models it describes.
  String get _prefix =>
      prefix ??
      (hasService<MetadataProvider>()
          ? getService<MetadataProvider>().scope
          : '');

  /// The state of [models], or of every replicated model when none is named.
  ///
  /// Returns null when the server cannot answer (an older server without the
  /// route, an unreachable one): the caller falls back to the manifest walk
  /// rather than skipping a sync it cannot prove is up to date.
  Future<Map<String, SyncModelState>?> fetch({List<String>? models}) async {
    final prefix = _prefix;
    final cached = _served(prefix, models);

    if (cached != null) {
      return cached;
    }

    try {
      final response = await _fetcher.get(
        '$prefix/dataset/sync-state',
        params: {
          if (models != null && models.isNotEmpty) 'models': models.join(','),
        },
      );
      final items = (response.data['items'] as List?) ?? const [];
      final states = {
        for (final item in items.whereType<Map<String, dynamic>>())
          '${item['model']}': SyncModelState.fromJson(item),
      };

      _answers[prefix] = (
        states: states,
        covered: models?.toSet(),
        at: DateTime.now(),
      );

      return states;
    } catch (error) {
      _logger.fine(
        'Sync state unavailable, falling back to the manifest',
        error,
      );

      return null;
    }
  }

  /// Forget the last answer: the next ask goes to the server.
  void invalidate() => _answers.clear();

  /// The last answer under [prefix], when it is still fresh and covered
  /// [models].
  Map<String, SyncModelState>? _served(String prefix, List<String>? models) {
    final answer = _answers[prefix];

    if (answer == null || DateTime.now().difference(answer.at) > freshness) {
      return null;
    }

    final covered = answer.covered;

    if (covered != null && (models == null || !covered.containsAll(models))) {
      return null;
    }

    return answer.states;
  }
}
