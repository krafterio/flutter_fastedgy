/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the asset paths the loader asks for, and an asset manifest listing
/// them, and nothing else, so a missing file is exercised as well as a present
/// one.
void _serve(Map<String, Map<String, String>> bundle) {
  TestWidgetsFlutterBinding.ensureInitialized();

  // rootBundle caches by key, so a second test would read the first one's
  // answer instead of the one just served.
  rootBundle.clear();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());

        if (key == 'AssetManifest.bin') {
          return const StandardMessageCodec().encodeMessage({
            for (final asset in bundle.keys) asset: <Object?>[],
          });
        }

        final payload = bundle[key];

        if (payload == null) {
          return null;
        }

        return ByteData.sublistView(utf8.encode(jsonEncode(payload)));
      });
}

const _framework = 'packages/flutter_fastedgy/assets/translations/fr.json';
const _application = 'assets/translations/fr.json';

void main() {
  group('FastEdgyAssetLoader', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    test(
      'hands the application its own words, never the framework ones',
      () async {
        _serve({
          _framework: {'Copy': 'Copier', 'Send': 'Envoyer'},
          _application: {'Flows': 'Flux'},
        });

        final loaded = await const FastEdgyAssetLoader().load(
          'assets/translations',
          const Locale('fr'),
        );

        expect(loaded, {'Flows': 'Flux'});
      },
    );

    test('a locale the application does not ship is null', () async {
      _serve({
        _framework: {'Copy': 'Copier'},
      });

      final loaded = await const FastEdgyAssetLoader().load(
        'assets/translations',
        const Locale('fr'),
      );

      expect(loaded, isNull);
    });
  });
}
