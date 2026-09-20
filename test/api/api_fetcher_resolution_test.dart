/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi({super.fetcher}) : super('/things');

  @override
  _Thing fromJson(Map<String, dynamic> json) => _Thing(json);
}

class _ThingResource extends ApiResource {
  _ThingResource({super.fetcher}) : super('/things');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    initializeContainer();
    container.reset();
    container.registerSingleton<Bus>(Bus());
  });

  tearDown(container.reset);

  test('a resource built before the container is populated still runs', () {
    // Providers are commonly built before initializeFastEdgy registers the
    // services they end up using.
    final api = _ThingApi();
    final resource = _ThingResource();

    container.registerSingleton<Fetcher>(
      Fetcher.create(dio: Dio(), enableLogging: false),
    );

    expect(api.fetcher, same(getService<Fetcher>()));
    expect(resource.fetcher, same(getService<Fetcher>()));
  });

  test('an injected fetcher is kept over the registered one', () {
    final injected = Fetcher.create(dio: Dio(), enableLogging: false);

    container.registerSingleton<Fetcher>(
      Fetcher.create(dio: Dio(), enableLogging: false),
    );

    expect(_ThingApi(fetcher: injected).fetcher, same(injected));
    expect(_ThingResource(fetcher: injected).fetcher, same(injected));
  });
}
