/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:get_it/get_it.dart';

abstract interface class _Resolver {}

class _Service {}

class _AppService extends _Service implements _Resolver {}

void main() {
  tearDown(container.reset);

  test('finds a subclass registered under the type it extends, as itself', () {
    final service = _AppService();
    container.registerSingleton<_Service>(service);

    expect(hasService<_AppService>(), isTrue);
    expect(getService<_AppService>(), same(service));
    expect(getService<_Service>(), same(service));
  });

  test('finds a service registered as itself under the type it extends', () {
    final service = _AppService();
    container.registerSingleton<_AppService>(service);

    expect(hasService<_Service>(), isTrue);
    expect(getService<_Service>(), same(service));
  });

  test('takes one instance registered under two types as one service', () {
    final service = _AppService();
    container.registerSingleton<_AppService>(service);
    container.registerSingleton<_Service>(service);

    expect(getService<_Resolver>(), same(service));
  });

  test('refuses to choose between two services, and finds none it lacks', () {
    container.registerSingleton<_AppService>(_AppService());
    container.registerSingleton<_Service>(_AppService());

    expect(() => getService<_Resolver>(), throwsStateError);
    expect(hasService<Bus>(), isFalse);
    expect(() => getService<Bus>(), throwsStateError);
  });

  test('remembers that none is a type, until a service is registered', () {
    expect(hasService<_AppService>(), isFalse);

    final service = _AppService();
    container.registerSingleton<_Service>(service);

    expect(getService<_AppService>(), same(service));
  });

  test('forgets what it found once the service is removed', () {
    container.registerSingleton<_Service>(_AppService());
    expect(hasService<_AppService>(), isTrue);

    container.unregister<_Service>();

    expect(hasService<_AppService>(), isFalse);
  });

  test('searches once, until a registration goes through the container', () {
    final service = _AppService();
    container.registerSingleton<_Service>(service);
    expect(getService<_Resolver>(), same(service));

    GetIt.instance.registerSingleton<_AppService>(_AppService());
    expect(getService<_Resolver>(), same(service));

    container.registerSingleton<Bus>(Bus());
    expect(() => getService<_Resolver>(), throwsStateError);
  });
}
