/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'list_support.dart';

class _Me extends BaseModel<_Me> {
  _Me(super.data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ViewServer views;
  late ThingApi api;

  setUp(() async {
    await setUpList(
      fields: {
        'status': metaField(
          'status',
          type: 'choice',
          label: 'Status',
          choices: {'open': 'Open'},
        ),
        'notes': metaField('notes', type: 'text', label: 'Notes'),
        'owner': metaField('owner', type: 'many2one', target: 'user'),
        'code': metaField('code', type: 'char'),
        'sequence': metaField('sequence', type: 'integer'),
        'files': metaField('files', type: 'one2many', target: 'file'),
      },
    );
    container.registerSingleton<UserProvider<_Me>>(
      UserProvider<_Me>(() async => _Me({'id': 5})),
    );
    await getService<UserProvider<_Me>>().load();
    server = ThingServer(rows: 3);
    views = ViewServer(server);
    api = ThingApi(server.fetcher);
  });

  List<String> keys(DataTable<Thing> table) => [
    for (final column in table.columns) column.key,
  ];

  List<MockRequest> layoutWrites() => [
    for (final request in server.requests)
      if (request.method != 'GET' && request.path.contains('/custom_views'))
        request,
  ];

  DataTable<Thing> tableOf({DataIteratorViews? opening}) => DataTable<Thing>(
    api,
    columns: const [
      DataTableColumn('name', width: 300),
      DataTableColumn('status'),
    ],
    layout: const DataTableLayout(),
    views: opening,
  );

  ColumnLayout layoutOf({ColumnStore? store}) => ColumnLayout(
    api,
    declared: const ['name', 'status'],
    prefix: '/acme',
    store: store,
    locked: const ['name'],
    exclude: const ['code'],
    delay: const Duration(milliseconds: 20),
  );

  group('the layout read', () {
    test('is the one of the user, else the one of everyone, else the columns declared', () async {
      final declared = tableOf();

      await settle();

      expect(keys(declared), ['name', 'status']);
      expect(sent(server.lists.last)['fields'], 'id,name,status');

      declared.dispose();
      views.add({
        'scope': 'layout',
        'display_fields': [
          'status',
          {'name': 'name', 'width': 280},
        ],
      });

      final shared = tableOf();

      await settle();

      expect(keys(shared), ['status', 'name']);
      expect(shared.columns.last.width, 280);
      expect(sent(server.lists.last)['fields'], 'id,status,name');

      shared.dispose();
      views.add({
        'scope': 'layout',
        'user': 5,
        'display_fields': ['notes', 'gone'],
      });

      final own = tableOf();

      await settle();

      expect(keys(own), ['notes']);
      expect(own.columns.single.title, 'Notes');
      expect(own.columns.single.filter, isA<TextColumnFilter>());
      expect(sent(server.lists.last)['fields'], 'id,notes');

      final custom = CustomViews('thing', list: own);

      await custom.ensure();

      expect(custom.items, isEmpty);

      own.dispose();
      custom.dispose();
    });

    test(
      'keeps a locked column, and offers the fields a column shows',
      () async {
        views.add({
          'scope': 'layout',
          'user': 5,
          'display_fields': ['status'],
        });

        final layout = layoutOf();

        await layout.load();

        expect(
          [for (final entry in layout.entries) entry.name],
          ['name', 'status'],
        );
        expect(
          [for (final field in layout.available) field.name],
          ['notes', 'owner'],
        );

        layout.dispose();
      },
    );
  });

  group('a change', () {
    test('shows at once and is written once a burst of them is over', () async {
      final layout = layoutOf();

      await layout.load();

      layout
        ..show('notes', at: 0)
        ..resize('notes', 120)
        ..move('status', 0)
        ..hide('name')
        ..resize('name', 120);

      expect(layout.entries, const [
        ColumnEntry('status'),
        ColumnEntry('notes', width: 120),
        ColumnEntry('name'),
      ]);
      expect(layoutWrites(), isEmpty);

      await until(() => layoutWrites().isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(layoutWrites().single.method, 'POST');
      expect(layoutWrites().single.body, {
        'name': 'List columns',
        'model': 'thing',
        'scope': 'layout',
        'user': 5,
        'display_fields': [
          'status',
          {'name': 'notes', 'width': 120},
          'name',
        ],
      });

      layout.resize('notes', defaultColumnWidth);

      expect(layout.entries[1], const ColumnEntry('notes'));

      await until(() => layoutWrites().length > 1);

      expect(layoutWrites().last.method, 'PATCH');
      expect(layoutWrites().last.body, {
        'display_fields': ['status', 'notes', 'name'],
      });

      layout.dispose();
    });

    test('goes back to the layout of everyone, the one of the user deleted, and is shared by who may', () async {
      views
        ..add({
          'scope': 'layout',
          'display_fields': ['status'],
          'editable': false,
        })
        ..add({
          'scope': 'layout',
          'user': 5,
          'display_fields': ['notes'],
        });

      final layout = layoutOf();

      await layout.load();

      expect(layout.canShare, isFalse);
      expect(layout.entries.last, const ColumnEntry('notes'));

      await layout.reset();

      expect(layoutWrites().single.method, 'DELETE');
      expect(layout.entries, const [
        ColumnEntry('name'),
        ColumnEntry('status'),
      ]);

      views.views.first['editable'] = true;
      await layout.load();

      expect(layout.canShare, isTrue);

      await layout.shareAsDefault();

      expect(layoutWrites().last.method, 'PATCH');
      expect(layoutWrites().last.body, {
        'display_fields': ['name', 'status'],
      });

      layout.dispose();
    });

    test('is kept in a store of the app', () async {
      final kept = <List<Object?>>[];
      final layout = layoutOf(
        store: ColumnStore(
          read: () async => ['status'],
          write: (entries) async => kept.add(entries),
        ),
      );

      await layout.load();

      expect(layout.entries, const [
        ColumnEntry('name'),
        ColumnEntry('status'),
      ]);
      expect(layout.canShare, isFalse);

      layout.hide('status');
      await until(() => kept.isNotEmpty);

      expect(kept, [
        ['name'],
      ]);
      expect(layoutWrites(), isEmpty);

      layout.dispose();
    });

    test(
      'reads the rows again for a column it has not read, not for one removed',
      () async {
        final table = tableOf();

        await settle();

        final reads = server.lists.length;

        table.layout!.show('notes');
        await settle();

        expect(server.lists, hasLength(reads + 1));
        expect(sent(server.lists.last)['fields'], 'id,name,status,notes');

        table.layout!.hide('status');
        await settle();

        expect(server.lists, hasLength(reads + 1));
        expect(keys(table), ['name', 'notes']);

        table.dispose();
      },
    );
  });

  group('a view', () {
    test('carries its columns: saved, shown, changed as the view, and a view without any leaves the layout', () async {
      final mine = views.add({
        'name': 'Mine',
        'display_fields': ['status'],
      });
      final bare = views.add({'name': 'Bare'});
      final table = tableOf(opening: const DataIteratorViews());
      final custom = CustomViews('thing', list: table);

      await settle();
      await custom.ensure();

      custom.apply(custom.items.firstWhere((view) => view.id == mine['id']));
      await settle();

      expect(keys(table), ['status']);
      expect(custom.modified, isFalse);

      table.layout!.show('notes');

      expect(keys(table), ['status', 'notes']);
      expect(custom.modified, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(layoutWrites(), isEmpty);

      await custom.save(custom.current!);

      expect(mine['display_fields'], ['status', 'notes']);

      custom.apply(custom.items.firstWhere((view) => view.id == bare['id']));
      await settle();

      expect(keys(table), ['name', 'status']);

      table.layout!.hide('status');

      expect(custom.modified, isFalse);

      table.dispose();
      custom.dispose();
    });
  });
}
