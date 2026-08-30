/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The smallest container a widget of `src/ui/` resolves against.
///
/// Only what the module itself asks for — an application's own services are
/// its business, and a suite that needs one is a suite that belongs to it.
///
/// Call from `setUp`; pair with [resetUiTestServices] in `tearDown`.
Future<void> setUpUiTestServices() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  if (!dotenv.isInitialized) {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  }

  initializeContainer();

  if (!hasService<Bus>()) {
    container.registerSingleton<Bus>(Bus());
  }

  if (!hasService<TokenStorage>()) {
    container.registerSingleton<TokenStorage>(const TokenStorage());
  }

  if (!hasService<TimezoneProvider>()) {
    container.registerSingleton<TimezoneProvider>(TimezoneProvider());
  }

  if (!hasService<Fetcher>()) {
    container.registerSingleton<Fetcher>(Fetcher.create(enableLogging: false));
  }

  if (!hasService<ImageCache>()) {
    container.registerSingleton<ImageCache>(ImageCache(getService<Bus>()));
  }

  // Without one, every mention comes home as plain text — which is the module's
  // documented behaviour and exactly what a suite about mentions must not test.
  if (!hasService<MentionAddressing>()) {
    container.registerSingleton<MentionAddressing>(const TestAddressing());
  }
}

void resetUiTestServices() {
  container.reset();
}

/// The shortest address that round-trips: `/r/{model}/{id}`.
class TestAddressing extends MentionAddressing {
  const TestAddressing();

  @override
  Uri? encode({required String model, required int id}) =>
      Uri.parse('/r/$model/$id');

  @override
  MentionAddress? decode(Uri uri) {
    final parts = uri.pathSegments;

    if (parts.length != 3 || parts.first != 'r') {
      return null;
    }

    final id = int.tryParse(parts[2]);

    return id == null
        ? null
        : MentionAddress(model: parts[1], id: id, uri: uri);
  }
}
