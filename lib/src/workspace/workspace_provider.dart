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
import '../auth/user_provider.dart';
import '../bus/bus.dart';
import '../bus/events.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
import '../fetcher/http_error.dart';
import '../logging/logger.dart';
import '../metadata/metadata_provider.dart';
import '../offline/offline_context_params.dart';
import '../realtime/realtime_events.dart';
import '../realtime/realtime_socket.dart';

/// The current workspace vanished from a list read again (the account was
/// removed from it, it was deleted). The one the account leaves itself is not
/// announced.
class WorkspaceLostEvent extends Event {
  const WorkspaceLostEvent(this.workspace);

  final BaseModel workspace;

  String get name => workspace.getString('name') ?? '';
}

/// Another workspace became the current one: every holder reads again, as for
/// any [ResourcesStaleEvent]; the provider itself has nothing to read again.
class WorkspaceSwitchedEvent extends ResourcesStaleEvent {
  const WorkspaceSwitchedEvent();
}

/// What the URL should say, given the slug it carries
/// ([WorkspaceProvider.resolve]).
sealed class WorkspaceDecision {
  const WorkspaceDecision();
}

/// The URL is right.
final class WorkspaceStay extends WorkspaceDecision {
  const WorkspaceStay();
}

/// The URL should carry [slug].
final class WorkspaceRedirect extends WorkspaceDecision {
  const WorkspaceRedirect(this.slug);

  final String slug;
}

/// The account has no workspace.
final class WorkspaceEmpty extends WorkspaceDecision {
  const WorkspaceEmpty();
}

/// The list of the account cannot be read.
final class WorkspaceFailed extends WorkspaceDecision {
  const WorkspaceFailed();
}

/// The account's workspaces and the current one, the tenant `/{workspace}`
/// stands for: chosen, followed and changed the way vue-fastedgy's
/// `useWorkspaceStore` does, case for case (the corpus `workspaces.json` both
/// packages run).
///
/// The choice, always after the account (`/me`, the registered [UserProvider]
/// or [account]): the slug of the URL as it is; without one, or once the
/// server refused it, the last workspace opened on this device
/// ([rememberLast]), then the account's default, then the first of the list.
/// The server decides whether a slug can be opened: the read of its metadatas
/// answering 404 refuses it, and the choice opens another one.
///
/// The workspaces augment the rest, which knows nothing of them: the provider
/// fills the `workspace` context param ([OfflineContextParams], the metadata
/// prefix included), and [WorkspacePrefixInterceptor] fills the requests.
/// Opt-in: an application serving one workspace at a time registers one under
/// this type, most often a subclass reading what its workspaces carry besides
/// ([loadRelated]).
class WorkspaceProvider<T extends BaseModel<T>> extends ChangeNotifier {
  WorkspaceProvider(
    this._model, {
    this._account,
    this._list,
    this.rememberLast = true,
    this.workspaceless,
    this.fields = 'id,name,slug',
  }) {
    final bus = getService<Bus>();
    bus.on<AuthLogoutEvent>().listen((_) => reset());
    bus.on<ResourceChangedEvent>().listen((event) {
      if (_loaded) {
        onResourceChanged(event);
      }
    });
    // A socket coming back missed what changed meanwhile; this provider's own
    // switch has nothing new to tell it.
    bus
        .on<ResourcesStaleEvent>()
        .where((event) => event is! WorkspaceSwitchedEvent)
        .listen((_) {
          if (_loaded) {
            unawaited(refresh());
          }
        });

    // The framework registers the context only for an offline app, the
    // metadata prefix resolves through it all the same.
    final params = hasService<OfflineContextParams>()
        ? getService<OfflineContextParams>()
        : container.registerSingleton(OfflineContextParams());
    params.register(_WorkspaceParams(this));

    if (hasService<RealtimeSocket>()) {
      final socket = getService<RealtimeSocket>();
      addListener(() => follow(socket));
    }
  }

  static const _rememberedKey = 'workspace.slug';
  static const _placeholder = '/{workspace}';
  static const _membershipModels = {'workspace', 'workspace_user'};

  final T Function(Map<String, dynamic>) _model;
  final Future<Object?> Function()? _account;
  final Future<List<T>> Function()? _list;
  final _log = getLogger('WorkspaceProvider');

  /// The last workspace opened on this device is the one opened next.
  final bool rememberLast;

  /// What a request under `/{workspace}` goes under when there is no
  /// workspace; `null` refuses it.
  final String? workspaceless;

  /// The columns the list carries (`X-Fields`).
  final String fields;

  List<T> _workspaces = const [];
  String? _slug;
  int? _currentId;
  bool _loading = false;
  bool _loaded = false;
  Object? _error;
  Future<T?>? _loadFuture;
  Future<T?>? _refreshing;
  bool _refreshAgain = false;
  String? _remembered;
  bool _rememberedRead = false;

  /// The slugs this session cannot open: refused by the server, lost or left.
  final _refused = <String>{};

  /// The id of a workspace renamed meanwhile, by a slug it had.
  final _renamed = <String, int>{};

  /// Bumped by a sign-out: a read for the account that left answers for nobody.
  int _generation = 0;

  /// Each list read and each local change takes a number: a read answering
  /// after a more recent one, or after a local change, tells an older list.
  int _sequence = 0;
  int _applied = 0;

  /// A workspace was opened this session: a list read then chooses none itself.
  bool _opened = false;

  /// The workspace being left: its disappearance is not a loss.
  int? _leaving;

  /// In the server's order.
  List<T> get workspaces => _workspaces;

  List<String> get slugs => [
    for (final workspace in _workspaces) _slugOf(workspace),
  ];

  T? get current => byId(_currentId) ?? bySlug(_slug);

  /// The slug of the current workspace, which a request under `/{workspace}`
  /// goes under.
  String? get slug => _slug;

  bool get loading => _loading;

  /// Whether the list has been read at least once (or failed, see [error]).
  bool get loaded => _loaded;

  /// What the last read of the list ran into, if it failed.
  Object? get error => _error;

  bool get hasWorkspaces => _workspaces.isNotEmpty;

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

    return workspace == null || _slugOf(workspace) == slug
        ? null
        : _slugOf(workspace);
  }

  /// Whether this session cannot open [slug]: the server refused it, or the
  /// account lost or left it.
  bool isRefused(String slug) => _refused.contains(slug);

  /// Whether [event] concerns the current workspace: its `workspace` field
  /// names it, or it names none (reading again only costs one read).
  bool concernsCurrent(ResourceChangedEvent event) {
    final workspace = event.data?['workspace'];

    return workspace == null || workspace == _currentId;
  }

  /// The workspaces of the account, read once, after the account itself.
  ///
  /// A failure stays the answer until [retry]: a router asks on each of its
  /// passes, and reading again there would turn a server that does not answer
  /// into a loop of requests. Nothing opened yet, the read opens the choice.
  Future<T?> load() {
    if (_loaded) {
      return Future.value(current);
    }

    return _loadFuture ??= _load(_generation);
  }

  Future<T?> _load(int asked) async {
    _loading = true;

    try {
      await _readRemembered();
      await _readAccount();

      // Signed out meanwhile: nothing to read for the account that left.
      if (asked != _generation) {
        return null;
      }

      await _read();

      if (asked == _generation) {
        if (!_opened && _slug == null) {
          _open(_choose());
        }

        unawaited(_related());
      }
    } catch (error, stackTrace) {
      if (asked == _generation) {
        _log.warning('Workspaces load failed', error, stackTrace);
        _error = error;
        _loaded = true;
        notifyListeners();
      }
    } finally {
      if (asked == _generation) {
        _loading = false;
        _loadFuture = null;
      }
    }

    return current;
  }

  /// Lets a failed read try again.
  Future<T?> retry() {
    _loaded = false;
    _error = null;
    _loadFuture = null;

    return load();
  }

  /// The list read again, and what comes with it ([loadRelated]). Called during
  /// such a read, it runs another one after: what changed meanwhile may be
  /// missing from the answer in progress. A failure keeps the list held.
  Future<T?> refresh() {
    final running = _refreshing;

    if (running != null) {
      _refreshAgain = true;

      return running;
    }

    return _refreshing = _refresh();
  }

  Future<T?> _refresh() async {
    try {
      do {
        _refreshAgain = false;

        try {
          await _read();
          await loadRelated();
        } catch (error, stackTrace) {
          _log.warning('Workspaces refresh failed', error, stackTrace);
        }
      } while (_refreshAgain);
    } finally {
      _refreshing = null;
    }

    return current;
  }

  /// For the interceptor: joins a read in progress rather than asking for
  /// another, otherwise a read of that one failing the same way would ask
  /// again, endlessly.
  Future<T?> refreshAfterError() => _refreshing ?? refresh();

  /// The current workspace, chosen when there is none yet: what a request
  /// under `/{workspace}` waits for.
  Future<String?> ensureCurrent() async {
    if (_slug != null) {
      return _slug;
    }

    await load();

    if (_slug == null) {
      _open(_choose());
    }

    return _slug;
  }

  /// What the URL should say, given the slug it carries.
  Future<WorkspaceDecision> resolve(String? slug) async {
    await _readRemembered();
    await _readAccount();

    final moved = slug == null ? null : renamedSlug(slug);

    if (moved != null) {
      _openSlug(moved);

      return WorkspaceRedirect(moved);
    }

    if (slug != null && !_refused.contains(slug)) {
      _openSlug(slug);
      unawaited(load());

      return const WorkspaceStay();
    }

    await load();

    if (_error != null) {
      return const WorkspaceFailed();
    }

    final pick = _choose();

    if (pick == null) {
      return const WorkspaceEmpty();
    }

    _open(pick);

    return WorkspaceRedirect(_slugOf(pick));
  }

  /// Makes [workspace] current. The URL follows it, through whoever navigates.
  void select(T workspace) => _open(workspace);

  /// Makes the workspace of [slug] current if the account has it.
  Future<bool> selectSlug(String slug) async {
    await load();

    final workspace = bySlug(slug);

    if (workspace != null) {
      _open(workspace);
    }

    return workspace != null;
  }

  /// Adds a workspace just created or joined, before the list read again says
  /// so. It only becomes current when none is: otherwise the URL picks it.
  void adopt(T workspace) {
    _applied = ++_sequence;
    _workspaces = List.unmodifiable([
      ..._workspaces.where((item) => item.id != workspace.id),
      workspace,
    ]);
    _loaded = true;
    _error = null;
    _refused.remove(_slugOf(workspace));
    // Before it opens: what this read brings along covers it.
    unawaited(refresh());

    if (_slug == null) {
      _open(workspace);
    }

    notifyListeners();
  }

  /// Creates a workspace (`POST /workspaces`) and makes it current.
  Future<T> create(Map<String, dynamic> payload) async {
    final response = await getService<Fetcher>().post('/workspaces', payload);
    final workspace = _model(response.data as Map<String, dynamic>);

    _applied = ++_sequence;
    _workspaces = List.unmodifiable([
      ..._workspaces.where((item) => item.id != workspace.id),
      workspace,
    ]);
    _refused.remove(_slugOf(workspace));
    _open(workspace);
    notifyListeners();

    return workspace;
  }

  /// Deletes a workspace (`DELETE /{slug}/workspace`); the choice follows when
  /// it was current.
  Future<T?> remove(String slug) async {
    await getService<Fetcher>().delete('/$slug/workspace');
    _drop(slug);

    return current;
  }

  /// Leaves the current workspace through [request] (the application's route);
  /// the choice follows. Noted before the request: a read answering meanwhile
  /// does not announce it lost.
  Future<T?> leave(Future<void> Function() request) async {
    final workspace = current;

    if (workspace == null) {
      return null;
    }

    _leaving = workspace.id;

    try {
      await request();
      _drop(_slugOf(workspace));
    } finally {
      _leaving = null;
    }

    return current;
  }

  /// Makes [slug] the account's default workspace, on the server: never a
  /// side effect of a choice.
  Future<void> makeDefault(String slug) async {
    await getService<Fetcher>().put('/workspaces/$slug/default', null);
    _workspaces = List.unmodifiable([
      for (final workspace in _workspaces)
        _model({...workspace.data, 'is_default': _slugOf(workspace) == slug}),
    ]);
    notifyListeners();
  }

  /// What the application reads along with the list (the current workspace's
  /// detail, the invitations), after each read of it and whenever another
  /// workspace becomes current. Nothing by default.
  @protected
  Future<void> loadRelated() async {}

  /// Reads the list again when a workspace or its members change.
  @protected
  void onResourceChanged(ResourceChangedEvent event) {
    if (_membershipModels.contains(event.model)) {
      unawaited(refresh());
    }
  }

  /// Whether a tenant request refused this way says the workspaces changed
  /// under the app (a 404: the workspace may be gone), for the interceptor to
  /// read them again.
  bool isWorkspaceError(int? status, Object? detail) => status == 404;

  /// Points the realtime socket at the current workspace, on each change.
  @protected
  void follow(RealtimeSocket socket) => socket.watch(_slug);

  /// Forgets the session's workspaces (a sign-out); what this device remembers
  /// stays.
  @protected
  @mustCallSuper
  void reset() {
    _generation++;
    _applied = ++_sequence;
    _workspaces = const [];
    _slug = null;
    _currentId = null;
    _loading = false;
    _loaded = false;
    _error = null;
    _loadFuture = null;
    _refreshing = null;
    _refused.clear();
    _renamed.clear();
    _opened = false;
    notifyListeners();
  }

  Future<void> _readRemembered() async {
    if (_rememberedRead) {
      return;
    }

    _rememberedRead = true;

    if (rememberLast) {
      _remembered ??= (await SharedPreferences.getInstance()).getString(
        _rememberedKey,
      );
    }
  }

  void _remember(String? slug) {
    if (!rememberLast) {
      return;
    }

    _remembered = slug;
    unawaited(
      SharedPreferences.getInstance().then(
        (preferences) => slug == null
            ? preferences.remove(_rememberedKey)
            : preferences.setString(_rememberedKey, slug),
      ),
    );
  }

  /// A failure of the account read is the list's to report: its read runs
  /// into the same.
  Future<void> _readAccount() async {
    try {
      final account = _account;

      if (account != null) {
        await account();
      } else if (hasService<UserProvider>()) {
        await getService<UserProvider>().load();
      }
    } catch (error) {
      _log.fine('Account load failed, reading the workspaces anyway', error);
    }
  }

  Future<void> _read() async {
    final asked = ++_sequence;
    final list = await _fetchList();

    if (asked < _applied) {
      return;
    }

    _applied = asked;
    _apply(list);
  }

  Future<List<T>> _fetchList() async {
    final list = _list;

    if (list != null) {
      return list();
    }

    final response = await getService<Fetcher>().get(
      '/workspaces',
      params: {'limit': 200},
      headers: {'X-Fields': fields},
    );
    final data = response.data;
    final items = data is Map ? data['items'] : null;

    return [
      if (items is List)
        for (final item in items)
          if (item is Map<String, dynamic>) _model(item),
    ];
  }

  void _apply(List<T> list) {
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

    final held = byId(_currentId) ?? bySlug(_slug);

    _currentId = held?.id;
    notifyListeners();

    if (held != null && _slugOf(held) != _slug) {
      _follow(_slugOf(held));
    } else if (previous != null && held == null && previous.id != _leaving) {
      getService<Bus>().fire(WorkspaceLostEvent(previous));
      _refuse(_slugOf(previous));
    }
  }

  void _open(T? workspace) {
    if (workspace != null) {
      _openSlug(_slugOf(workspace), workspace);
    }
  }

  /// Makes [value] current, remembers it on this device and reads its
  /// metadatas; every screen reads again when another one was current.
  void _openSlug(String value, [T? workspace]) {
    if (value.isEmpty || value == _slug) {
      return;
    }

    final previous = _slug;

    _slug = value;
    _currentId = (workspace ?? bySlug(value))?.id;
    _opened = true;
    _remember(value);
    notifyListeners();
    unawaited(_probe(value));

    if (previous != null) {
      getService<Bus>().fire(const WorkspaceSwitchedEvent());
    }

    // A read of the list under way brings it along as it ends.
    if (_loaded && _loadFuture == null && _refreshing == null) {
      unawaited(_related());
    }
  }

  Future<void> _related() async {
    try {
      await loadRelated();
    } catch (error, stackTrace) {
      _log.warning('Workspace related load failed', error, stackTrace);
    }
  }

  /// The current workspace renamed: the same one, under its new slug.
  void _follow(String value) {
    _slug = value;
    _remember(value);
    notifyListeners();
    unawaited(_probe(value));
  }

  /// Reads the metadatas of [value], the first request under its slug: the
  /// server refusing it (404) is the account not being a member.
  Future<void> _probe(String value) async {
    if (!hasService<MetadataProvider>()) {
      return;
    }

    final metadata = getService<MetadataProvider>();

    if (!(metadata.prefix ?? '').contains(_placeholder)) {
      return;
    }

    await metadata.getMetadatas();

    final error = metadata.error;

    if (_slug == value &&
        error is HttpError &&
        error.statusCode == 404 &&
        (error.response?.requestOptions.path ?? '').contains('/$value/')) {
      _refuse(value);
    }
  }

  /// This session cannot open [value] any more: forgotten by the device, and
  /// the choice opens another one in its place when it was current.
  void _refuse(String value) {
    _refused.add(value);

    if (_remembered == value) {
      _remember(null);
    }

    if (_slug == value) {
      final pick = _loaded ? _choose() : null;

      if (pick != null) {
        _open(pick);
      } else {
        _slug = null;
        _currentId = null;

        if (!_loaded) {
          unawaited(
            load().then((_) {
              if (_slug == null) {
                _open(_choose());
              }
            }),
          );
        }
      }
    }

    notifyListeners();
  }

  /// Drops a workspace the account no longer has; the choice follows when it
  /// was current.
  void _drop(String slug) {
    _applied = ++_sequence;
    _workspaces = List.unmodifiable(
      _workspaces.where((item) => _slugOf(item) != slug),
    );
    _refuse(slug);
  }

  /// The workspace to open when nothing names one: the last one of this
  /// device, then the account's default, then the first; never one this
  /// session cannot open.
  T? _choose() {
    final open = _workspaces.where(
      (workspace) => !_refused.contains(_slugOf(workspace)),
    );
    final last = _remembered;

    return (last == null
            ? null
            : open
                  .where((workspace) => _slugOf(workspace) == last)
                  .firstOrNull) ??
        open
            .where((workspace) => workspace.getBool('is_default') ?? false)
            .firstOrNull ??
        open.firstOrNull;
  }

  static String _slugOf(BaseModel workspace) =>
      workspace.getString('slug') ?? '';
}

/// The `workspace` context param: what `/{workspace}` resolves to, the
/// metadata prefix included.
class _WorkspaceParams implements OfflineContextParamsResolver {
  _WorkspaceParams(this._workspaces);

  final WorkspaceProvider _workspaces;

  @override
  Map<String, Object?> resolve() => {'workspace': _workspaces.slug};
}
