/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_model_engine.dart';
import '../api/base_model.dart';
import '../auth/auth_events.dart';
import '../bus/bus.dart';
import '../bus/events.dart';
import '../container/container.dart';
import '../logging/logger.dart';
import '../metadata/metadata_provider.dart';
import '../offline/offline_context_params.dart';
import '../realtime/realtime_events.dart';
import '../realtime/realtime_socket.dart';

/// The current workspace vanished from a list read again (the account was
/// removed from it, it was deleted): another one replaced it, or none did.
class WorkspaceLostEvent extends Event {
  const WorkspaceLostEvent(this.workspace);

  final BaseModel workspace;

  String get name => workspace.getString('name') ?? '';
}

/// The account's workspaces and the current one, the tenant `/{workspace}`
/// stands for: in a request path ([WorkspacePrefixInterceptor]), in the
/// metadata prefix and in the offline context, which is why it registers
/// itself in [OfflineContextParams]. The counterpart of vue-fastedgy's
/// `useWorkspaceStore` with `createFetcher({ workspace: true })`.
///
/// Opt-in: an application serving one workspace at a time registers one, most
/// often a subclass reading what its workspaces carry besides
/// ([loadRelated]).
///
/// The workspaces are the account's: given an [account] read, the list is
/// read once it answered (`/me` first). The schema is the current
/// workspace's: its metadata are read once one is chosen.
///
/// The current one is tracked by its id: a slug renamed meanwhile is found
/// again in the list read again, and [renamedSlug] leads the old one to the
/// new. One that vanishes from such a list fires [WorkspaceLostEvent], except
/// the one the account [leave]s itself.
class WorkspaceProvider<T extends BaseModel<T>> extends ChangeNotifier
    implements OfflineContextParamsResolver {
  WorkspaceProvider(this._loader, {this._account}) {
    final bus = getService<Bus>();
    bus.on<AuthLogoutEvent>().listen((_) => reset());
    bus.on<ResourceChangedEvent>().listen((event) {
      if (_loaded) {
        onResourceChanged(event);
      }
    });
    bus.on<ResourcesStaleEvent>().listen((_) {
      if (_loaded) {
        unawaited(refresh());
      }
    });

    // The framework registers the context only for an offline app, the
    // metadata prefix resolves through it all the same.
    final params = hasService<OfflineContextParams>()
        ? getService<OfflineContextParams>()
        : container.registerSingleton(OfflineContextParams());
    params.register(this);

    if (hasService<RealtimeSocket>()) {
      final socket = getService<RealtimeSocket>();
      addListener(() => follow(socket));
    }
  }

  static const _rememberedKey = 'workspace.slug';

  final Future<List<T>> Function() _loader;
  final Future<Object?> Function()? _account;
  final _log = getLogger('WorkspaceProvider');

  List<T> _workspaces = const [];
  int? _currentId;
  bool _loaded = false;
  Object? _error;
  Future<void>? _initialization;
  Future<void>? _refreshing;
  bool _refreshAgain = false;
  String? _remembered;

  /// The workspace the account is leaving: its disappearance is not a loss.
  int? _leaving;

  /// The old slugs of a workspace renamed while the app held it, by id.
  final _renamed = <String, int>{};

  /// Each read of the list and each local change takes a number: a read that
  /// answers after a more recent one, or after a local change, is ignored (it
  /// would tell an older list).
  int _sequence = 0;
  int _applied = 0;

  @override
  Map<String, Object?> resolve() => {'workspace': currentSlug};

  /// In the server's order.
  List<T> get workspaces => _workspaces;

  List<String> get slugs => [
    for (final workspace in _workspaces) _slugOf(workspace),
  ];

  T? get current => byId(_currentId);

  String? get currentSlug {
    final workspace = current;

    return workspace == null ? null : _slugOf(workspace);
  }

  /// Whether the list has been read at least once (or failed, see [error]).
  bool get isLoaded => _loaded;

  /// What the last read of the list ran into, if it failed.
  Object? get error => _error;

  bool get hasWorkspaces => _workspaces.isNotEmpty;

  /// Whether [event] concerns the current workspace: its `workspace` field
  /// names it, or it names none (reading again only costs one read).
  bool concernsCurrent(ResourceChangedEvent event) {
    final workspace = event.data?['workspace'];

    return workspace == null || workspace == _currentId;
  }

  T? byId(int? id) => id == null
      ? null
      : _workspaces.where((workspace) => workspace.id == id).firstOrNull;

  T? bySlug(String? slug) => slug == null
      ? null
      : _workspaces
            .where((workspace) => _slugOf(workspace) == slug)
            .firstOrNull;

  /// The present slug of the workspace that was called [slug], if it was
  /// renamed.
  String? renamedSlug(String slug) {
    final workspace = byId(_renamed[slug]);

    return workspace == null ? null : _slugOf(workspace);
  }

  /// Reads the workspaces, once per session. The current one is
  /// [preferredSlug] (the URL's) if it is in the list, otherwise the
  /// [defaultOf] the list, otherwise the first.
  ///
  /// A failure stays the answer until [retry]: a router calls this on each of
  /// its passes, and reading again there would turn a server that does not
  /// answer into a loop of requests.
  Future<void> initialize({String? preferredSlug}) {
    if (_loaded) {
      return Future.value();
    }

    final running = _initialization;

    if (running != null) {
      return running;
    }

    late final Future<void> run;
    run = _initialize(preferredSlug).whenComplete(() {
      if (identical(_initialization, run)) {
        _initialization = null;
      }
    });

    return _initialization = run;
  }

  Future<void> _initialize(String? preferredSlug) async {
    await _readAccount();
    _remembered ??= (await SharedPreferences.getInstance()).getString(
      _rememberedKey,
    );

    try {
      await _read(preferredSlug);
    } catch (error) {
      // The first authenticated read of a session races the sign-in: the event
      // a router redirects on is fired from the call that is still setting
      // the tokens, and the read can come back as a 401. A second read, once
      // the loop has passed; a second failure is a real one.
      _log.fine(
        'Workspaces load failed, reading again once the session has settled',
        error,
      );

      try {
        await Future<void>.delayed(Duration.zero);
        await _read(preferredSlug);
      } catch (error, stackTrace) {
        _log.warning('Workspaces load failed', error, stackTrace);
        _error = error;
        _loaded = true;
        notifyListeners();

        return;
      }
    }

    unawaited(_afterRead());
  }

  /// A failure of the account read is the list's to report: its read runs
  /// into the same.
  Future<void> _readAccount() async {
    final account = _account;

    if (account == null) {
      return;
    }

    try {
      await account();
    } catch (error) {
      _log.fine('Account load failed, reading the workspaces anyway', error);
    }
  }

  /// Reads everything again: after a failure, or for a session that opens
  /// (never what a previous one read).
  Future<void> retry() {
    _loaded = false;
    _error = null;
    _initialization = null;

    return initialize();
  }

  /// Reads the list again, and what comes with it. Called during such a read,
  /// it runs another one after: what changed meanwhile may be missing from the
  /// answer in progress.
  Future<void> refresh() {
    final running = _refreshing;

    if (running != null) {
      _refreshAgain = true;

      return running;
    }

    return _refreshing = _runRefresh();
  }

  /// For the interceptor: joins a read in progress rather than asking for
  /// another, otherwise a read of that one failing the same way would ask for
  /// one again, endlessly.
  Future<void> refreshAfterError() => _refreshing ?? refresh();

  Future<void> _runRefresh() async {
    try {
      do {
        _refreshAgain = false;

        try {
          await _read();
          await _afterRead();
        } catch (error, stackTrace) {
          _log.warning('Workspaces refresh failed', error, stackTrace);
        }
      } while (_refreshAgain);
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _read([String? preferredSlug]) async {
    final sequence = ++_sequence;
    final list = await _loader();

    if (sequence < _applied) {
      return;
    }

    _applied = sequence;
    _apply(list, preferredSlug);
  }

  void _apply(List<T> list, String? preferredSlug) {
    for (final workspace in list) {
      final before = byId(workspace.id);

      if (before != null && _slugOf(before) != _slugOf(workspace)) {
        _renamed[_slugOf(before)] = workspace.id!;
      }
    }

    final previous = current;
    _workspaces = List.unmodifiable(list);
    _loaded = true;
    _error = null;
    _currentId =
        (byId(_currentId) ??
                bySlug(preferredSlug) ??
                defaultOf(list) ??
                list.firstOrNull)
            ?.id;
    notifyListeners();

    if (previous != null &&
        byId(previous.id) == null &&
        previous.id != _leaving) {
      getService<Bus>().fire(WorkspaceLostEvent(previous));
    }
  }

  /// What a read of the list brings along: the current workspace's metadata,
  /// and what [loadRelated] adds.
  Future<void> _afterRead() async {
    if (_currentId != null && hasService<MetadataProvider>()) {
      unawaited(
        getService<MetadataProvider>().getMetadatas().then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) =>
              _log.warning('Metadata load failed', error, stackTrace),
        ),
      );
    }

    await loadRelated();
  }

  /// What the application reads along with the list (the current workspace's
  /// detail, the invitations), after each read of it. Nothing by default.
  @protected
  Future<void> loadRelated() async {}

  /// The workspace to open when the URL names none of the account's: the one
  /// [remember] kept on this device, as vue-fastedgy does. An application
  /// keeping the choice elsewhere (on the server, to follow the account from
  /// one device to another) overrides both.
  @protected
  T? defaultOf(List<T> workspaces) => _remembered == null
      ? null
      : workspaces
            .where((workspace) => _slugOf(workspace) == _remembered)
            .firstOrNull;

  /// Keeps [workspace] as the one to open next time, see [defaultOf].
  @protected
  Future<void> remember(T workspace) async {
    final slug = _remembered = _slugOf(workspace);
    await (await SharedPreferences.getInstance()).setString(
      _rememberedKey,
      slug,
    );
  }

  /// Makes [workspace] current and [remember]s it; nothing for the one that
  /// already is. The switch is immediate, the future completes once the
  /// choice is kept.
  Future<void> select(T workspace) async {
    if (workspace.id == _currentId) {
      return;
    }

    _currentId = workspace.id;
    notifyListeners();

    // Everything on screen belonged to the workspace left behind: each holder
    // reads again, this provider included.
    getService<Bus>().fire(const ResourcesStaleEvent());

    try {
      await remember(workspace);
    } catch (error, stackTrace) {
      _log.warning('Workspace choice not kept', error, stackTrace);
    }
  }

  /// Makes the workspace of [slug] current if the account is a member of it.
  Future<bool> selectSlug(String slug) async {
    await initialize(preferredSlug: slug);

    final workspace = bySlug(slug);

    if (workspace == null) {
      return false;
    }

    unawaited(select(workspace));

    return true;
  }

  /// Adds a workspace just created or joined, before the list read again says
  /// so (and lists the others).
  ///
  /// It only becomes current if it is the only one: otherwise the URL picks it,
  /// as for any workspace. Picked here, a router would swap it right back for
  /// the one of the URL still shown.
  void adopt(T workspace) {
    _applied = ++_sequence;
    _workspaces = List.unmodifiable([
      ..._workspaces.where((item) => item.id != workspace.id),
      workspace,
    ]);
    _loaded = true;
    _error = null;
    _currentId ??= workspace.id;
    notifyListeners();
    unawaited(refresh());
  }

  /// Leaves the current workspace through [request]; the [defaultOf] or the
  /// first of the others becomes current, if any remain. Noted before the
  /// request: a read answering meanwhile does not report it lost.
  Future<void> leave(Future<void> Function() request) async {
    final workspace = current;

    if (workspace == null) {
      return;
    }

    _leaving = workspace.id;

    try {
      await request();

      _applied = ++_sequence;
      _workspaces = List.unmodifiable(
        _workspaces.where((item) => item.id != workspace.id),
      );
      _currentId = (defaultOf(_workspaces) ?? _workspaces.firstOrNull)?.id;
      notifyListeners();
    } finally {
      _leaving = null;
    }

    unawaited(_afterRead());
  }

  /// Reads the list again when a workspace or its members change.
  @protected
  void onResourceChanged(ResourceChangedEvent event) {
    if (event.model == 'workspace' || event.model == 'workspace_user') {
      unawaited(refresh());
    }
  }

  /// Whether a tenant request refused this way says the workspaces changed
  /// under the app (the workspace is gone: a 404), for the interceptor to read
  /// them again.
  bool isWorkspaceError(int? status, Object? detail) => status == 404;

  /// Points the realtime socket at the current workspace, on each change.
  @protected
  void follow(RealtimeSocket socket) => socket.watch(currentSlug);

  /// Forgets the session's workspaces (a sign-out).
  @protected
  @mustCallSuper
  void reset() {
    _applied = ++_sequence;
    _workspaces = const [];
    _currentId = null;
    _loaded = false;
    _error = null;
    _initialization = null;
    _renamed.clear();
    notifyListeners();
  }

  static String _slugOf(BaseModel workspace) =>
      workspace.getString('slug') ?? '';
}
