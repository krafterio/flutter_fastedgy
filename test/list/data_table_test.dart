/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/list.dart';
import 'package:flutter_fastedgy/workspace.dart' show WorkspaceSwitchedEvent;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_metadata.dart';
import 'list_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThingServer server;
  late ThingApi api;
  late FakeMetadataProvider metadata;

  setUp(() async {
    metadata = await setUpList(
      fields: {
        'initials': metaField('initials', type: 'computed', label: 'Initials'),
        'status': metaField(
          'status',
          type: 'choice',
          label: 'Status',
          choices: {'open': 'Open', 'done': 'Done'},
        ),
        'owner': metaField('owner', type: 'many2one', target: 'user'),
      },
    );
    metadata.models['user'] = metaModel(
      'user',
      fields: {'name': metaField('name', type: 'char', label: 'Owner name')},
    );
    server = ThingServer();
    api = ThingApi(server.fetcher);
  });

  test(
    'takes from the metadata what its columns do not say, and reads them',
    () async {
      final table = DataTable<Thing>(
        api,
        columns: [
          const DataTableColumn('name'),
          const DataTableColumn('initials'),
          const DataTableColumn('status', filterable: true),
          const DataTableColumn('owner.name', sortable: false, label: 'Who'),
          const DataTableColumn('missing', type: 'date'),
          const DataTableColumn('owner', filterable: true),
        ],
        additionalFields: ['owner.id'],
      );

      await settle();

      final [name, initials, status, owner, missing, relation] = table.columns;

      expect((name.title, name.type, name.isSortable), ('name', 'char', true));
      expect((initials.title, initials.isSortable), ('Initials', false));
      expect(status.filter, isA<ChoiceColumnFilter>());
      expect(
        (owner.title, owner.meta?.label, owner.isSortable),
        ('Who', 'Owner name', false),
      );
      expect(
        (missing.meta, missing.type, missing.isSortable),
        (null, 'date', false),
      );
      expect(
        sent(server.lists.single)['fields'],
        'id,name,initials,status,owner.name,missing,owner,owner.id',
      );
      expect(relation.filter, isA<RelationColumnFilter>());
      expect(table.pageSize, 100);
      expect(table.availablePageSizes, [25, 50, 100, 150, 200]);

      table.dispose();
    },
  );

  test('reads again for a column it has not read', () async {
    final table = DataTable<Thing>(
      api,
      columns: [const DataTableColumn('name')],
    );

    await settle();
    table.columns = [
      const DataTableColumn('name'),
      const DataTableColumn('status'),
    ];
    await settle();

    expect(sent(server.lists.last)['fields'], 'id,name,status');
    expect(table.columns.last.meta?.label, 'Status');

    table.dispose();
  });

  test('resolves its columns again from the metadata of the workspace it switches to', () async {
    final table = DataTable<Thing>(
      api,
      columns: [const DataTableColumn('name')],
    );

    await settle();
    metadata.models['thing'] = metaModel(
      'thing',
      apiName: 'things',
      fields: {'name': metaField('name', type: 'text', label: 'Title')},
    );
    getService<Bus>().fire(const WorkspaceSwitchedEvent());
    await settle();

    expect(table.columns.single.title, 'Title');
    expect(table.columns.single.type, 'text');

    table.dispose();
  });

  test('reads the fields of its tiles, sized for a grid', () async {
    final grid = DataGrid<Thing>(
      api,
      fields: ['name'],
      additionalFields: ['status'],
    );

    await settle();

    expect(sent(server.lists.single)['fields'], 'id,name,status');
    expect(sent(server.lists.single)['limit'], 24);
    expect(grid.availablePageSizes, [12, 24, 48, 96]);

    grid.dispose();
  });

  test('opens a table and a grid on their custom views', () async {
    ViewServer(server).add({
      'name': 'Everyone',
      'is_default': true,
      'order_by': ['name:asc'],
    });

    final table = DataTable<Thing>(
      api,
      columns: const [DataTableColumn('name')],
      views: const DataIteratorViews(),
    );
    final grid = DataGrid<Thing>(
      api,
      fields: ['name'],
      views: const DataIteratorViews(),
    );

    await settle();

    expect(table.orderBy, ['name:asc']);
    expect(grid.orderBy, ['name:asc']);

    table.dispose();
    grid.dispose();
  });
}
