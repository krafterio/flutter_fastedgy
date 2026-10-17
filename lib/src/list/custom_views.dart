/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';
import '../auth/user_provider.dart';
import '../bus/bus.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
import '../query/query_expression.dart' show sameExpression;
import '../workspace/workspace_provider.dart' show WorkspaceSwitchedEvent;
import 'data_iterator.dart';

const _viewFields =
    'id,name,model,scope,user,filters,order_by,group_by,display_fields,'
    'sequence,is_default,editable';

/// A custom view of a list: its filters, its order, its grouping, its columns
/// and what a screen adds to it, for its user alone or for everyone.
class CustomView extends BaseModel<CustomView> {
  CustomView(super.data);

  String get name => getString('name') ?? '';

  /// The metadata name of the model listed.
  String? get model => getString('model');

  /// The list among those of the model, `''` for its default one.
  String get scope => getString('scope') ?? '';

  /// Whether every user sees it, rather than its author alone.
  bool get shared => data['user'] == null;

  Object? get filters => data['filters'];

  List<String>? get orderBy => getStringList('order_by');

  String? get groupBy => getString('group_by');

  List<Object?>? get displayFields => data['display_fields'] as List<Object?>?;

  /// The favorite of everyone, the view a list opens on for a user who chose
  /// none.
  bool get isDefault => data['is_default'] == true;

  /// Whether the user may change it.
  bool get editable => data['editable'] == true;

  /// What the view holds under [name], a field of the screen's own.
  Object? operator [](String name) => data[name];
}

/// The view a list opens on for one account, its own favorite: a row of
/// `custom_view_favorite`, apart from the favorite of everyone a view carries
/// ([CustomView.isDefault]).
class CustomViewFavorite extends BaseModel<CustomViewFavorite> {
  CustomViewFavorite(super.data);

  /// The id of the view, read as an id or as the view itself.
  Object? get viewId => _idOf(data['view']);

  /// The view itself, when it was read with its fields (`view.name`…).
  CustomView? get view {
    final view = data['view'];

    return view is Map<String, dynamic> ? CustomView(view) : null;
  }
}

class _ViewApi extends ApiModel<CustomView> {
  _ViewApi(super.basePath, {super.fetcher}) : super(modelName: 'custom_view');

  @override
  CustomView fromJson(Map<String, dynamic> json) => CustomView(json);
}

class _FavoriteApi extends ApiModel<CustomViewFavorite> {
  _FavoriteApi(super.basePath, {super.fetcher})
    : super(modelName: 'custom_view_favorite');

  @override
  CustomViewFavorite fromJson(Map<String, dynamic> json) =>
      CustomViewFavorite(json);
}

List<List<Object?>> _listOf(String model, String scope) => [
  ['model', '=', model],
  ['scope', '=', scope],
];

List<List<Object?>> _favoritesOf(String model, String scope) => [
  ['view.model', '=', model],
  ['view.scope', '=', scope],
];

Object? _idOf(Object? value) => value is Map ? value['id'] : value;

String _json(Object? value) => jsonEncode(value, toEncodable: (_) => null);

/// The view a list of [model] opens on: the one a link names ([id]), kept only
/// when it is one of this list, else the favorite of the user, else the one
/// of everyone, else none. A failure is no view.
Future<CustomView?> openingView(
  String model, {
  String scope = '',
  String prefix = '',
  int? id,
  Fetcher? fetcher,
}) async {
  final views = _ViewApi(prefix, fetcher: fetcher);

  try {
    if (id != null) {
      final named = await views.get(
        id,
        options: const FieldsOptions(fields: _viewFields),
      );

      return named.model == model && named.scope == scope ? named : null;
    }

    final (own, shared) = await (
      _FavoriteApi(prefix, fetcher: fetcher).list(
        query: ListQuery(
          size: 1,
          fields: [
            'id',
            for (final field in _viewFields.split(',')) 'view.$field',
          ],
          filter: _favoritesOf(model, scope),
        ),
      ),
      views.list(
        query: ListQuery(
          size: 1,
          fields: _viewFields,
          filter: [
            ..._listOf(model, scope),
            ['is_default', 'is true'],
          ],
        ),
      ),
    ).wait;
    return own.items.firstOrNull?.view ?? shared.items.firstOrNull;
  } catch (_) {
    return null;
  }
}

/// What a view holds besides its filters and its order, by field of the view
/// (`group_by`): applied when the list opens on it, unless the URL says it
/// under [key], applied and saved with it by [CustomViews].
class ViewStateField {
  const ViewStateField({required this.get, required this.set, this.key});

  /// What the list holds now.
  final Object? Function() get;

  /// Holds what a view says, null when it says nothing.
  final void Function(Object? value) set;

  /// The key of the URL the screen keeps it under.
  final String? key;
}

/// The custom views a list opens on, the `views` option of a [DataIterator].
class DataIteratorViews {
  const DataIteratorViews({
    this.scope = '',
    this.prefix,
    this.state = const {},
  });

  /// The list among those of the model, `''` for its default one.
  final String scope;

  /// Where the views are read, where the api model of the list answers
  /// otherwise.
  final String? prefix;

  /// What the views hold besides the filters and the order.
  final Map<String, ViewStateField> state;
}

/// The custom views of a list, the port of `useCustomViews`: read once its
/// menu opens, applied to [list], saved from what it shows. What the server
/// refuses is thrown to the caller, the screen showing it. In another
/// workspace, the views read are forgotten, and those of the new one read
/// again when they had been.
class CustomViews extends ChangeNotifier {
  CustomViews(
    this.model, {
    String? scope,
    String? prefix,
    this.list,
    Fetcher? fetcher,
  }) : scope = scope ?? list?.views?.scope ?? '',
       _views = _ViewApi(
         prefix ?? list?.viewsPrefix ?? '',
         fetcher: fetcher ?? list?.api.fetcher,
       ),
       _favorites = _FavoriteApi(
         prefix ?? list?.viewsPrefix ?? '',
         fetcher: fetcher ?? list?.api.fetcher,
       ) {
    // The list opens on what this menu reads: one read for both.
    list?.customViews ??= this;

    if (hasService<Bus>()) {
      _switches = getService<Bus>().on<WorkspaceSwitchedEvent>().listen(
        (_) => _forget(),
      );
    }
  }

  /// The metadata name of the model listed.
  final String model;

  final String scope;

  /// The list the views read and are applied to.
  final DataIterator<dynamic>? list;

  final _ViewApi _views;
  final _FavoriteApi _favorites;

  List<CustomView> _items = const [];
  ({Object? id, Object? view})? _favorite;
  bool _loading = false;
  bool _loaded = false;
  Object? _error;
  Future<void>? _reading;
  StreamSubscription<WorkspaceSwitchedEvent>? _switches;

  // Bumped by a workspace switch: a read answering for the one before lands
  // nowhere.
  int _generation = 0;

  /// The views of the list, in their order.
  List<CustomView> get items => _items;

  /// The id of the favorite view of the user.
  Object? get favorite => _favorite?.view;

  bool get loading => _loading;

  bool get loaded => _loaded;

  Object? get error => _error;

  /// The view the list is on.
  CustomView? get current =>
      _items.where((view) => view.id == list?.view).firstOrNull;

  /// Whether the list moved away from its view: its filters, its order, its
  /// grouping, its columns when the view has some, or what the view holds
  /// besides.
  bool get modified {
    final view = current;
    final list = this.list;

    if (view == null || list == null) {
      return false;
    }

    return !sameExpression(view.filters, list.expression) ||
        _json(view.orderBy ?? list.defaultOrderBy) != _json(list.orderBy) ||
        list.groupByOf(view.groupBy) != list.groupBy ||
        (view.displayFields != null &&
            _json(view.displayFields) != _json(list.displayFields)) ||
        list.viewState.entries.any(
          (one) => _json(view[one.key]) != _json(one.value.get()),
        );
  }

  /// Reads the views once, the calls made meanwhile sharing the read.
  Future<void> ensure() {
    if (_loaded) {
      return Future.value();
    }

    final running = _reading;

    if (running != null) {
      return running;
    }

    late final Future<void> reading;

    // A read forgotten by a workspace switch leaves the one after it alone.
    reading = refresh().whenComplete(() {
      if (identical(_reading, reading)) {
        _reading = null;
      }
    });

    return _reading = reading;
  }

  /// Reads the views again.
  Future<void> refresh() async {
    final generation = _generation;

    _loading = true;
    notifyListeners();

    try {
      final views = _views.list(
        query: ListQuery(
          size: 100,
          fields: _viewFields,
          filter: _listOf(model, scope),
        ),
      );
      final own = _favorites.list(
        query: ListQuery(
          size: 1,
          fields: 'id,view',
          filter: _favoritesOf(model, scope),
        ),
      );

      await Future.wait([views, own], eagerError: true);

      if (generation != _generation) {
        return;
      }

      final first = (await own).items.firstOrNull;

      _items = (await views).items;
      _favorite = first == null ? null : (id: first.id, view: first.viewId);
      _error = null;
      _loaded = true;

      final on = current;

      if (on != null) {
        _follow(on);
      }
    } catch (failure) {
      if (generation != _generation) {
        return;
      }

      _error = failure;

      rethrow;
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Another workspace: the views held are the one before's, and those of
  /// the new one are read when these had been.
  void _forget() {
    final read = _loaded;

    _generation++;
    _items = const [];
    _favorite = null;
    _error = null;
    _loaded = false;
    _loading = false;
    _reading = null;
    notifyListeners();

    if (read) {
      unawaited(ensure().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    unawaited(_switches?.cancel());

    if (identical(list?.customViews, this)) {
      list?.customViews = null;
    }

    super.dispose();
  }

  /// Keeps what the list shows as a new view, which becomes the current one.
  Future<CustomView> create({required String name, bool shared = true}) async {
    final created = await _views.create(
      CustomView({
        'name': name,
        'model': model,
        // The default list is the scope the server writes: an empty one
        // would leave as null, which the field refuses.
        if (scope.isNotEmpty) 'scope': scope,
        'user': shared ? null : _account(),
        ..._state(),
      }),
      options: const FieldsOptions(fields: _viewFields),
    );

    _items = [..._items, created];
    list?.view = created.id;
    _follow(created);
    notifyListeners();

    return created;
  }

  /// Writes what the list shows into [view].
  Future<void> save(CustomView view) async {
    final saved = await _views.update(
      view.id!,
      CustomView(_state()),
      options: const FieldsOptions(fields: _viewFields),
    );

    _replace(saved);

    if (list?.view == saved.id) {
      _follow(saved);
    }

    notifyListeners();
  }

  Future<void> rename(CustomView view, String name) async {
    _replace(
      await _views.update(
        view.id!,
        CustomView({'name': name}),
        options: const FieldsOptions(fields: _viewFields),
      ),
    );
    notifyListeners();
  }

  /// Deletes [view], and forgets it as the favorite and as the current view.
  Future<void> remove(CustomView view) async {
    await _views.delete(view.id!);

    _items = [
      for (final item in _items)
        if (item.id != view.id) item,
    ];

    if (_favorite?.view == view.id) {
      _favorite = null;
    }

    final list = this.list;

    if (list != null && list.view == view.id) {
      list.view = null;
      _follow(null);
    }

    notifyListeners();
  }

  /// Makes [view] the one the list opens on for everyone, or stops; the
  /// others lose theirs on the screen.
  Future<void> setDefault(CustomView view, bool on) async {
    final saved = await _views.update(
      view.id!,
      CustomView({'is_default': on}),
      options: const FieldsOptions(fields: _viewFields),
    );

    _items = [
      for (final item in _items)
        item.id == saved.id
            ? saved
            : on && item.isDefault
            ? CustomView({...item.data, 'is_default': false})
            : item,
    ];
    notifyListeners();
  }

  /// Makes [view] the one the list opens on for the user, or stops.
  Future<void> setFavorite(CustomView view, bool on) async {
    if (on) {
      final created = await _favorites.create(
        CustomViewFavorite({'view': view.id}),
        options: const FieldsOptions(fields: 'id,view'),
      );

      _favorite = (id: created.id, view: view.id);
      notifyListeners();

      return;
    }

    final favorite = _favorite;

    if (favorite?.view == view.id && favorite?.id != null) {
      await _favorites.delete(favorite!.id!);
      _favorite = null;
      notifyListeners();
    }
  }

  /// Shows [view] in the list: its filters, its order and its grouping (the
  /// list's own when it has none), its columns, what it holds besides, and
  /// itself as the current view. The search stays.
  void apply(CustomView view) {
    final list = this.list;

    if (list == null) {
      return;
    }

    list
      ..expression = view.filters
      ..orderBy = view.orderBy ?? list.defaultOrderBy
      ..groupBy = list.groupByOf(view.groupBy)
      ..view = view.id
      ..applyView(view, const {});
    _follow(view);
  }

  Map<String, Object?> _state() {
    final list = this.list;

    return {
      'filters': list?.expression,
      'order_by': list?.orderBy,
      // The field itself, `none` for a flat list that groups by default.
      'group_by':
          list?.groupBy ?? (list?.defaultGroupBy == null ? null : 'none'),
      'display_fields': ?list?.displayFields,
      for (final MapEntry(key: name, value: one)
          in list?.viewState.entries ??
              const <MapEntry<String, ViewStateField>>[])
        name: one.get(),
    };
  }

  void _replace(CustomView view) {
    _items = [
      for (final item in _items)
        if (item.id == view.id) view else item,
    ];
  }

  /// Tells the list the filters of the view it is on, which it then keeps
  /// out of its URL.
  void _follow(CustomView? view) {
    final list = this.list;

    if (list == null) {
      return;
    }

    if (view == null) {
      list.forgetViewExpression();
    } else {
      list.viewExpression = view.filters;
    }
  }

  static Object? _account() {
    if (!hasService<UserProvider<dynamic>>()) {
      return null;
    }

    final user = getService<UserProvider<dynamic>>().user;

    return user is BaseModel ? user.id : null;
  }
}

/// What the menu of a view offers.
enum ViewAction {
  /// Make a shared view the one everyone opens on.
  favoriteForEveryone,

  /// Stop that.
  notFavoriteForEveryone,

  rename,
  delete,
}

/// The menu of [view]: the favorite of everyone for a shared one, renaming
/// and deleting; nothing for a view the user may not change.
List<ViewAction> viewActions(CustomView view) => view.editable
    ? [
        if (view.shared)
          view.isDefault
              ? ViewAction.notFavoriteForEveryone
              : ViewAction.favoriteForEveryone,
        ViewAction.rename,
        ViewAction.delete,
      ]
    : const [];

/// Whether the current view can be written with what the list shows: the
/// list moved away from it, and the user may change it.
bool canUpdateView(CustomViews views) =>
    views.modified && (views.current?.editable ?? false);

/// Whether what the list shows can be kept as a view: at least one condition.
bool canSaveView(int count) => count > 0;
