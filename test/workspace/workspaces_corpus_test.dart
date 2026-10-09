/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// This package held to the workspace corpus vue-fastedgy runs on the very same
// file: a case passing on one side only is a behavior that differs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_fastedgy/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Workspace extends BaseModel<_Workspace> {
  _Workspace(super.data);
}

class _SignedIn implements AuthProvider {
  @override
  Future<bool> isAuthenticated() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final Map<String, dynamic> _corpus = jsonDecode(
  File('test/fixtures/workspaces.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> _listOf(List<dynamic> names) {
  final fixtures = _corpus['workspaces'] as Map<String, dynamic>;

  return {
    'status': 200,
    'body': {
      'items': [for (final name in names) fixtures[name]],
      'total': names.length,
    },
  };
}

Object? _decisionOf(WorkspaceDecision decision) => switch (decision) {
  WorkspaceStay() => 'stay',
  WorkspaceEmpty() => 'empty',
  WorkspaceFailed() => 'failed',
  WorkspaceRedirect(:final slug) => {'redirect': slug},
};

int _byName(String one, String other) => one.compareTo(other);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(container.reset);

  for (final testCase
      in (_corpus['cases'] as List).cast<Map<String, dynamic>>()) {
    test(testCase['name'], () async {
      final options = (testCase['options'] as Map<String, dynamic>?) ?? {};
      final device = testCase['device'] as String?;
      final routes = <String, dynamic>{
        ...(_corpus['server'] as Map<String, dynamic>),
        ...((testCase['server'] as Map<String, dynamic>?) ?? {}),
        if (testCase['list'] != null)
          'GET /workspaces': _listOf(testCase['list'] as List),
      };
      var sent = <String>[];
      var events = <String>[];

      SharedPreferences.setMockInitialValues({'workspace.slug': ?device});
      initializeContainer();

      final bus = container.registerSingleton<Bus>(Bus());
      final fetcher = container.registerSingleton<Fetcher>(
        createMockFetcher((request) {
          final key = '${request.method} ${request.path}';
          final answer =
              (routes[key] as Map<String, dynamic>?) ??
              {
                'status': 404,
                'body': {'detail': 'Not Found'},
              };
          final status = answer['status'] as int;

          sent.add(key);

          if (status >= 300) {
            return MockResponse.error(status, body: answer['body']);
          }

          return answer['body'] == null
              ? MockResponse.empty(statusCode: status)
              : MockResponse.json(answer['body'], statusCode: status);
        }, customInterceptors: [WorkspacePrefixInterceptor()]),
      );

      container.registerSingleton<AuthProvider>(_SignedIn());
      container.registerSingleton<UserProvider<Map<String, dynamic>>>(
        UserProvider<Map<String, dynamic>>(
          () async => (await fetcher.get('/me')).data as Map<String, dynamic>,
        ),
      );

      final provider = container.registerSingleton<WorkspaceProvider>(
        WorkspaceProvider<_Workspace>(
          _Workspace.new,
          rememberLast: (options['rememberLast'] as bool?) ?? true,
          workspaceless: options['workspaceless'] as String?,
        ),
      );

      container.registerSingleton<MetadataProvider>(
        DefaultMetadataProvider(fetcher, getService<AuthProvider>(), bus)
          ..setPrefix('/{workspace}'),
      );

      bus.on<ResourcesStaleEvent>().listen((_) => events.add('stale'));
      bus.on<WorkspaceLostEvent>().listen(
        (event) => events.add('lost:${event.name}'),
      );

      for (final step
          in (testCase['steps'] as List).cast<Map<String, dynamic>>()) {
        routes.addAll((step['server'] as Map<String, dynamic>?) ?? {});

        if (step['list'] != null) {
          routes['GET /workspaces'] = _listOf(step['list'] as List);
        }

        sent = [];
        events = [];

        Object? decision;
        var failed = false;

        if (step.containsKey('open')) {
          decision = _decisionOf(
            await provider.resolve(step['open'] as String?),
          );
        } else if (step.containsKey('select')) {
          provider.select(provider.bySlug(step['select'] as String)!);
        } else if (step.containsKey('makeDefault')) {
          await provider.makeDefault(step['makeDefault'] as String);
        } else if (step['logout'] == true) {
          bus.fire(const AuthLogoutEvent());
        } else if (step.containsKey('request')) {
          final [method, path] = (step['request'] as String).split(' ');

          try {
            await switch (method) {
              'GET' => fetcher.get(path),
              'DELETE' => fetcher.delete(path),
              _ => fetcher.post(path, null),
            };
          } catch (_) {
            failed = true;
          }
        } else if (step.containsKey('change')) {
          bus.fire(
            ResourceChangedEvent(
              null,
              model: step['change'] as String,
              type: ResourceChangeType.updated,
            ),
          );
        } else if (step.containsKey('leave')) {
          final [_, path] = (step['leave'] as String).split(' ');

          await provider.leave(() async {
            await fetcher.delete(path);
          });
        }

        await pumpEventQueue(times: 50);

        final expected = (step['expect'] as Map<String, dynamic>?) ?? {};
        final at = jsonEncode(step);
        final preferences = await SharedPreferences.getInstance();

        if (expected.containsKey('decision')) {
          expect(decision, expected['decision'], reason: at);
        }

        if (expected.containsKey('slug')) {
          expect(provider.slug, expected['slug'], reason: at);
        }

        if (expected.containsKey('requests')) {
          expect(
            [...sent]..sort(_byName),
            [...(expected['requests'] as List).cast<String>()]..sort(_byName),
            reason: at,
          );
        }

        for (final pair in (expected['order'] as List?) ?? const []) {
          final [before, after] = (pair as List).cast<String>();

          expect(
            sent.indexOf(before),
            lessThan(sent.indexOf(after)),
            reason: '$at: $before before $after',
          );
        }

        if (expected.containsKey('device')) {
          expect(
            preferences.getString('workspace.slug'),
            expected['device'],
            reason: at,
          );
        }

        if (expected.containsKey('events')) {
          expect(events, expected['events'], reason: at);
        }

        if (expected.containsKey('sent')) {
          expect(sent, contains(expected['sent']), reason: at);
        }

        if (expected.containsKey('failed')) {
          expect(failed, expected['failed'], reason: at);
        }

        if (expected.containsKey('default')) {
          expect(
            provider.workspaces
                .where((workspace) => workspace.getBool('is_default') ?? false)
                .firstOrNull
                ?.getString('slug'),
            expected['default'],
            reason: at,
          );
        }
      }
    });
  }
}
