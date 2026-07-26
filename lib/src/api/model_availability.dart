/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bus/bus.dart';
import '../container/container.dart';
import '../metadata/metadata_provider.dart';
import '../sync/sync_status.dart';

/// What a model lets a client do away from the server, and whether this build
/// is wired to honour it.
///
/// Pure facts: no connectivity, no read, nothing to dispose. Combine them with
/// how reachable the server is — [canWrite] — to get an answer. A widget that
/// wants that answer kept up to date binds to [ModelAvailability] instead.
class ModelCapability {
  /// `full`, `partial` or `none`, as the server declares it in the metadata.
  final String synchronizableMode;

  /// Whether a write made while the server is unreachable is buffered for a
  /// later replay instead of failing.
  final bool bufferizesWrites;

  const ModelCapability({
    this.synchronizableMode = 'none',
    this.bufferizesWrites = false,
  });

  /// Nothing known yet — the metadata never arrived. Reads and writes are
  /// assumed to need the server, which is what an unreplicated model does.
  static const unknown = ModelCapability();

  /// Whether reads may be served locally at all. It promises nothing about what
  /// is actually mirrored: a replicated model still comes back empty until a
  /// read or a sync has filled it.
  bool get isReplicated => synchronizableMode != 'none';

  /// Whether the mirror only holds what earlier reads happened to return
  /// (`partial`) rather than every record (`full`).
  bool get isPartiallyMirrored => synchronizableMode == 'partial';

  /// Whether an action on this model is worth offering: always while the server
  /// answers, and otherwise only if the write would be buffered and replayed.
  bool canWrite({required bool serverReachable}) =>
      serverReachable || bufferizesWrites;

  /// The capability of [modelName], read from the metadata.
  ///
  /// The write path is detected through [SyncStatus], registered with the outbox
  /// itself, so this stays in the API layer instead of reaching into the offline
  /// module. Resolve through `ApiModel.capability()` instead when a resource
  /// instance is at hand — it asks its own engine.
  static Future<ModelCapability> of(String modelName) async {
    if (!hasService<MetadataProvider>()) {
      return unknown;
    }

    final meta = await getService<MetadataProvider>().getMetadata(modelName);

    if (meta == null) {
      return unknown;
    }

    return ModelCapability(
      synchronizableMode: meta.synchronizableMode,
      bufferizesWrites: meta.synchronizable && hasService<SyncStatus>(),
    );
  }
}

/// Live answer to "what can I do with this model right now", with no read behind
/// it.
///
/// For anything acting on a model without holding its data: a toolbar or header
/// button, a menu entry, a dialog opened from another screen. It resolves the
/// [ModelCapability] once and then follows connectivity, notifying on every
/// change, so a button re-enables itself the moment the server is back.
///
/// ```dart
/// final _access = ModelAvailability('flow');
///
/// ListenableBuilder(
///   listenable: _access,
///   builder: (context, _) => Button(
///     label: t(`New flow`),
///     onTap: _access.canWrite ? _newFlow : null,
///   ),
/// )
/// ```
///
/// [ApiCollection] and [ApiRecord] answer the same question from their own
/// state; this is for everything that has neither.
class ModelAvailability extends ChangeNotifier {
  final String modelName;

  ModelCapability _capability = ModelCapability.unknown;
  bool _resolved = false;
  StreamSubscription<SyncStatusChangedEvent>? _sub;

  ModelAvailability(this.modelName) {
    _sub = getService<Bus>().on<SyncStatusChangedEvent>().listen((_) {
      notifyListeners();
    });
    _resolve();
  }

  Future<void> _resolve() async {
    _capability = await ModelCapability.of(modelName);
    _resolved = true;

    if (_sub != null) {
      notifyListeners();
    }
  }

  /// Whether the metadata answered. Before that the capability is
  /// [ModelCapability.unknown]: an action stays offered while the server is
  /// reachable, and is held back while it is not.
  bool get resolved => _resolved;

  ModelCapability get capability => _capability;

  /// Connectivity as the sync layer knows it.
  bool get serverReachable => SyncStatus.currentlyOnline;

  /// Whether an action on this model is worth offering right now.
  bool get canWrite => _capability.canWrite(serverReachable: serverReachable);

  /// Whether reading this model right now needs the server — the state a screen
  /// or a menu entry announces instead of showing nothing.
  bool get requiresConnection => !serverReachable && !_capability.isReplicated;

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

/// One-shot version of [ModelAvailability.canWrite], for a callback that only
/// needs the answer once — a menu item deciding whether to open a form, a guard
/// at the top of an action handler.
Future<bool> canWriteModel(String modelName) async => (await ModelCapability.of(
  modelName,
)).canWrite(serverReachable: SyncStatus.currentlyOnline);
