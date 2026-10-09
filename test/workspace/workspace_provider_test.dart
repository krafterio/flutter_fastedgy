/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_metadata.dart';

class _Workspace extends BaseModel<_Workspace> {
  _Workspace(super.data);
}

_Workspace _workspace(int id, String slug) =>
    _Workspace({'id': id, 'slug': slug, 'name': slug.toUpperCase()});

/// Records the tenant each read of the metadata resolved to.
class _Metadata extends FakeMetadataProvider {
  _Metadata() : super(const {});

  final scopes = <Object?>[];

  @override
  Future<Map<String, MetadataModel>?> getMetadatas() {
    scopes.add(getService<OfflineContextParams>().resolve()['workspace']);

    return super.getMetadatas();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Workspace> list;

  WorkspaceProvider<_Workspace> provider({
    Future<Object?> Function()? account,
  }) => WorkspaceProvider<_Workspace>(() async => list, account: account);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    initializeContainer();
    container.registerSingleton<Bus>(Bus());
    list = [_workspace(1, 'alpha'), _workspace(2, 'beta')];
  });

  tearDown(container.reset);

  test(
    "opens the URL's workspace, else the one chosen last, else the first",
    () async {
      final first = provider();
      await first.initialize();
      expect(first.currentSlug, 'alpha');

      await first.select(list[1]);

      final next = provider();
      await next.initialize();
      expect(next.currentSlug, 'beta');

      final linked = provider();
      await linked.initialize(preferredSlug: 'alpha');
      expect(linked.currentSlug, 'alpha');
    },
  );

  test('reads the list once the account answered', () async {
    final account = Completer<Object?>();
    var reads = 0;
    final workspaces = WorkspaceProvider<_Workspace>(() async {
      reads++;

      return list;
    }, account: () => account.future);

    final initialized = workspaces.initialize();
    await pumpEventQueue();
    expect(reads, 0);

    account.complete('ada');
    await initialized;
    expect(reads, 1);
  });

  test('reads the metadata of the workspace once it is chosen', () async {
    final metadata = _Metadata();
    container.registerSingleton<MetadataProvider>(metadata);

    final workspaces = provider();
    await workspaces.initialize();
    await pumpEventQueue();

    expect(metadata.scopes, ['alpha']);
  });

  test('reports the current workspace lost, not the one it leaves', () async {
    final lost = <String>[];
    getService<Bus>().on<WorkspaceLostEvent>().listen(
      (event) => lost.add(event.name),
    );
    final workspaces = provider();
    await workspaces.initialize();

    await workspaces.leave(() async => list = [_workspace(2, 'beta')]);
    await workspaces.refresh();
    await pumpEventQueue();
    expect(workspaces.currentSlug, 'beta');
    expect(lost, isEmpty);

    list = [];
    await workspaces.refresh();
    await pumpEventQueue();
    expect(workspaces.current, isNull);
    expect(lost, ['BETA']);
  });

  group('WorkspacePrefixInterceptor', () {
    late WorkspaceProvider<_Workspace> workspaces;
    late List<String> paths;

    setUp(() {
      paths = [];
      workspaces = provider();
      container.registerSingleton<Fetcher>(
        createMockFetcher((request) {
          paths.add(request.path);

          return request.path == '/alpha/gone'
              ? const MockResponse.error(404)
              : const MockResponse.json({});
        }, customInterceptors: [WorkspacePrefixInterceptor(() => workspaces)]),
      );
    });

    test(
      'puts the current slug in the path, and drops a request without one',
      () async {
        final fetcher = getService<Fetcher>();

        await expectLater(fetcher.get('/{workspace}/notes'), throwsA(anything));
        expect(paths, isEmpty);

        await workspaces.initialize();
        await fetcher.get('/{workspace}/notes');
        await fetcher.get('/workspaces');
        expect(paths, ['/alpha/notes', '/workspaces']);
      },
    );

    test('reads the workspaces again when the workspace is gone', () async {
      await workspaces.initialize();
      list = [_workspace(2, 'beta')];

      await expectLater(
        getService<Fetcher>().get('/{workspace}/gone'),
        throwsA(anything),
      );
      await pumpEventQueue();

      expect(workspaces.currentSlug, 'beta');
    });
  });
}
