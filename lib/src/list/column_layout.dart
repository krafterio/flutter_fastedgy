/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_model.dart';
import '../api/api_query.dart';
import '../api/base_model.dart';
import '../auth/user_provider.dart';
import '../container/container.dart';
import '../metadata/models.dart';
import 'sortable.dart';

/// The width of a column that says none: it keeps its own.
const defaultColumnWidth = 200;

/// The widths a column offers, by their label.
const columnWidths = [
  (label: 'Compact', width: 120),
  (label: 'Normal', width: defaultColumnWidth),
  (label: 'Large', width: 280),
];

/// The fields no column shows: the record itself, its search, its order, its
/// owners.
const _hidden = {
  'id',
  'search_value',
  'image',
  'created_by',
  'updated_by',
  'workspace',
  'sequence',
};

/// The types a column shows.
const _shown = {
  'char',
  'text',
  'rich_text',
  'url',
  'email',
  'phone',
  'integer',
  'float',
  'decimal',
  'boolean',
  'date',
  'datetime',
  'time',
  'choice',
  'many2one',
  'many2many',
};

/// A column shown: its field, and its width when it is not the default one.
@immutable
class ColumnEntry {
  const ColumnEntry(this.name, {int? width})
    : width = width == defaultColumnWidth ? null : width;

  /// An entry as `display_fields` keeps it: a name, or a name and a width.
  static ColumnEntry? read(Object? raw) => switch (raw) {
    String() when raw.isNotEmpty => ColumnEntry(raw),
    {'name': final String name, 'width': final num width} => ColumnEntry(
      name,
      width: width.toInt(),
    ),
    {'name': final String name} => ColumnEntry(name),
    _ => null,
  };

  final String name;

  /// Its width, null for the default one.
  final int? width;

  /// The entry as `display_fields` keeps it.
  Object toJson() => width == null ? name : {'name': name, 'width': width};

  @override
  bool operator ==(Object other) =>
      other is ColumnEntry && other.name == name && other.width == width;

  @override
  int get hashCode => Object.hash(name, width);
}

/// Where a layout is kept in place of the custom views of the model: the
/// columns of a collection, for one. It reads and writes the entries as
/// `display_fields` keeps them.
class ColumnStore {
  const ColumnStore({required this.read, required this.write});

  final Future<List<Object?>?> Function() read;
  final Future<void> Function(List<Object?> entries) write;
}

Object? _account() {
  if (!hasService<UserProvider<dynamic>>()) {
    return null;
  }

  final user = getService<UserProvider<dynamic>>().user;

  return user is BaseModel ? user.id : null;
}

/// The columns a list shows, their order and their width, the port of
/// Kascade's `useListLayout`: those of the user, else those of everyone,
/// else the columns declared. A change shows at once and is written once the
/// changes of a moment are over, as a custom view without filters of the
/// scope `layout` (`layout:<scope>`), which no menu of views lists. On a view
/// that carries its columns, a change is one of the view instead.
class ColumnLayout extends ChangeNotifier {
  ColumnLayout(
    this.api, {
    required List<String> declared,
    this.scope = '',
    String? prefix,
    this.store,
    this.locked = const [],
    this.exclude = const [],
    this.delay = const Duration(milliseconds: 500),
  }) : _declared = [for (final name in declared) ColumnEntry(name)],
       _views = GenericApiModel(
         prefix ?? apiPrefixOf(api),
         modelName: 'custom_view',
         fetcher: api.fetcher,
       );

  final ApiModel<dynamic> api;

  /// The list among those of the model, `''` for its default one.
  final String scope;

  /// Where the layout is kept, the custom views of the model otherwise.
  final ColumnStore? store;

  /// The columns that move, but are neither removed nor resized.
  final List<String> locked;

  /// The fields never offered.
  final List<String> exclude;

  /// How long the changes of a moment wait before they are written.
  final Duration delay;

  final GenericApiModel _views;

  List<ColumnEntry> _declared;
  List<ColumnEntry>? _own;
  List<ColumnEntry>? _shared;
  List<ColumnEntry>? _view;
  Object? _ownId;
  Object? _sharedId;
  bool? _sharedEditable;
  MetadataModel? _meta;
  bool _loading = false;
  Object? _error;
  bool _disposed = false;
  Timer? _pending;
  Future<void> _writes = Future.value();

  /// The columns shown, in their order.
  List<ColumnEntry> get entries => _view ?? _own ?? _shared ?? _declared;

  /// The columns shown, as `display_fields` keeps them.
  List<Object> get written => [for (final entry in entries) entry.toJson()];

  /// The fields a column can be added for: those a column shows, but the
  /// technical ones, those excluded and those shown.
  List<MetadataField> get available {
    final shown = {for (final entry in entries) entry.name};

    return [
      for (final field in _meta?.fields.values ?? const <MetadataField>[])
        if (_shown.contains(field.type) &&
            !_hidden.contains(field.name) &&
            !exclude.contains(field.name) &&
            !shown.contains(field.name))
          field,
    ];
  }

  /// Whether the layout of everyone can be written by the user.
  bool get canShare => store == null && (_sharedEditable ?? true);

  bool get loading => _loading;

  /// What the last read or write failed with.
  Object? get error => _error;

  String get _scope => scope.isEmpty ? 'layout' : 'layout:$scope';

  /// The names of the columns declared, shown when no layout says otherwise.
  set declared(List<String> names) {
    _declared = [for (final name in names) ColumnEntry(name)];
    notifyListeners();
  }

  /// [raw] as entries, the locked columns kept, the fields gone left out.
  List<ColumnEntry>? _entriesOf(Object? raw) {
    if (raw is! List) {
      return null;
    }

    final known = {..._meta?.fields.keys ?? const <String>[]};
    final declared = {for (final entry in _declared) entry.name};
    final entries = [
      for (final one in raw)
        if (ColumnEntry.read(one) case final entry?)
          if (_meta == null ||
              known.contains(entry.name) ||
              declared.contains(entry.name))
            entry,
    ];
    final names = {for (final entry in entries) entry.name};

    return [
      for (final name in locked)
        if (!names.contains(name)) ColumnEntry(name),
      ...entries,
    ];
  }

  /// Reads the layout of the user, else the one of everyone, and the fields
  /// a column can show; again in another workspace.
  Future<void> load() async {
    _loading = true;
    notifyListeners();

    try {
      _meta = await api.metadata();

      final store = this.store;

      if (store != null) {
        _own = _entriesOf(await store.read());
      } else {
        final views = await _views.list(
          query: ListQuery(
            size: 10,
            fields: 'id,user,display_fields,editable',
            filter: [
              ['model', '=', await api.resolveModelName()],
              ['scope', '=', _scope],
            ],
          ),
        );
        final own = views.items.where((view) => view.data['user'] != null);
        final shared = views.items.where((view) => view.data['user'] == null);

        _ownId = own.firstOrNull?.id;
        _own = _entriesOf(own.firstOrNull?.data['display_fields']);
        _sharedId = shared.firstOrNull?.id;
        _shared = _entriesOf(shared.firstOrNull?.data['display_fields']);
        _sharedEditable = shared.firstOrNull?.data['editable'] as bool?;
      }

      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;

      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Shows the columns of a view, null for none: the layout again.
  void applyView(List<Object?>? fields) {
    _view = _entriesOf(fields);
    notifyListeners();
  }

  /// Adds the column of [name], at [at] or last.
  void show(String name, {int? at}) {
    if (entries.any((entry) => entry.name == name)) {
      return;
    }

    final next = [...entries];

    next.insert((at ?? next.length).clamp(0, next.length), ColumnEntry(name));
    _change(next);
  }

  /// Removes the column of [name], unless it is locked.
  void hide(String name) {
    if (locked.contains(name)) {
      return;
    }

    _change([
      for (final entry in entries)
        if (entry.name != name) entry,
    ]);
  }

  /// Puts the column of [name] at [index].
  void move(String name, int index) {
    final next = [...entries];
    final at = next.indexWhere((entry) => entry.name == name);

    if (at < 0) {
      return;
    }

    next.insert(index.clamp(0, next.length - 1), next.removeAt(at));
    _change(next);
  }

  /// Gives the column of [name] a width, its own for null or the default
  /// one, unless it is locked.
  void resize(String name, int? width) {
    if (locked.contains(name)) {
      return;
    }

    _change([
      for (final entry in entries)
        entry.name == name ? ColumnEntry(name, width: width) : entry,
    ]);
  }

  /// Goes back to the layout of everyone, else to the columns declared: the
  /// one of the user is forgotten, the one of a view left.
  Future<void> reset() {
    _pending?.cancel();
    _pending = null;
    _view = null;
    _own = null;
    notifyListeners();

    return _write(() async {
      final store = this.store;

      if (store != null) {
        await store.write([for (final entry in _declared) entry.toJson()]);

        return;
      }

      final id = _ownId;

      if (id != null) {
        await _views.delete(id);
        _ownId = null;
      }
    });
  }

  /// Makes the columns shown those of everyone without a layout of their
  /// own.
  Future<void> shareAsDefault() {
    final shown = [...entries];

    return _write(() async {
      _sharedId = await _save(_sharedId, shown, user: null);
      _shared = shown;
    });
  }

  void _change(List<ColumnEntry> next) {
    if (_view != null) {
      _view = next;
      notifyListeners();

      return;
    }

    _own = next;
    notifyListeners();
    _pending?.cancel();
    _pending = Timer(delay, _flush);
  }

  void _flush() {
    _pending = null;

    final own = _own;

    if (own == null) {
      return;
    }

    unawaited(
      _write(() async {
        final store = this.store;

        if (store != null) {
          await store.write([for (final entry in own) entry.toJson()]);
        } else {
          _ownId = await _save(_ownId, own, user: _account());
        }
      }),
    );
  }

  /// Writes [entries] into the layout [id], created when there is none, and
  /// gives its id.
  Future<Object?> _save(
    Object? id,
    List<ColumnEntry> entries, {
    required Object? user,
  }) async {
    final fields = [for (final entry in entries) entry.toJson()];

    if (id != null) {
      await _views.update(id, GenericBaseModel({'display_fields': fields}));

      return id;
    }

    final created = await _views.create(
      GenericBaseModel({
        'name': 'List columns',
        'model': await api.resolveModelName(),
        'scope': _scope,
        'user': user,
        'display_fields': fields,
      }),
      options: const FieldsOptions(fields: 'id'),
    );

    return created.id;
  }

  /// Runs [write] after those before it, its failure kept as the [error].
  Future<void> _write(Future<void> Function() write) =>
      _writes = _writes.then((_) async {
        try {
          await write();
          _error = null;
        } catch (error) {
          _error = error;
        }

        if (!_disposed) {
          notifyListeners();
        }
      });

  @override
  void dispose() {
    _disposed = true;

    // A change of the last moment is written all the same.
    if (_pending?.isActive ?? false) {
      _pending!.cancel();
      _flush();
    }

    super.dispose();
  }
}
