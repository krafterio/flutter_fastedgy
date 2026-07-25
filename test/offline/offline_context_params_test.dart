/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

/// A tenant reached by slug but mirrored by id, as a workspace is.
class _MockTenant implements OfflineScopeParamsResolver {
  String slug = 'acme';
  int? id = 7;

  @override
  Map<String, Object?> resolve() => {'workspace': slug};

  @override
  Map<String, Object?> resolveScope() => {'workspace': id};
}

/// A resolver that never heard of scopes: its substitution values are its
/// scope, as before.
class _MockLocale implements OfflineContextParamsResolver {
  @override
  Map<String, Object?> resolve() => {'locale': 'fr'};
}

void main() {
  test('scopes by the declared scope value, substitutes by the other', () {
    final params = OfflineContextParams()..register(_MockTenant());

    expect(params.scopeOf('/{workspace}'), '7');
    expect(params.contextFor('/{workspace}'), {'workspace': 'acme'});
    expect(
      OfflineContextParams.substituteWith(
        '/{workspace}/projects',
        params.resolve(),
      ),
      '/acme/projects',
    );
  });

  test('a renamed tenant keeps its scope', () {
    final tenant = _MockTenant();
    final params = OfflineContextParams()..register(tenant);

    tenant.slug = 'acme-renamed';

    // What the mirror is keyed by does not move, so nothing written under the
    // former slug is stranded.
    expect(params.scopeOf('/{workspace}'), '7');
    expect(params.contextFor('/{workspace}'), {'workspace': 'acme-renamed'});
  });

  test('a resolver without a scope is scoped by what it substitutes', () {
    final params = OfflineContextParams()..register(_MockLocale());

    expect(params.scopeOf('/{locale}'), 'fr');
    expect(params.contextFor('/{locale}'), {'locale': 'fr'});
  });

  test('an unresolved scope leaves the resource global', () {
    final tenant = _MockTenant()..id = null;
    final params = OfflineContextParams()..register(tenant);

    expect(params.scopeOf('/{workspace}'), '');
    // The path is still substitutable: only the mirror has nowhere to go.
    expect(params.contextFor('/{workspace}'), {'workspace': 'acme'});
  });
}
