/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_fastedgy/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends BaseModel<_Thing> {
  _Thing(super.data);
}

class _ThingApi extends ApiModel<_Thing> {
  _ThingApi(super.basePath, {super.modelName, super.fetcher});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Fetcher fetcher;

  setUp(() {
    initializeContainer();

    if (!hasService<Bus>()) {
      container.registerSingleton<Bus>(Bus());
    }

    fetcher = createMockFetcher(
      (_) => const MockResponse.json({}),
      enableAuth: false,
      enableTimezone: false,
      enableRefreshToken: false,
    );
  });

  group('isAbout', () {
    test('matches the model an event names', () {
      final api = _ThingApi(
        '/{workspace}',
        modelName: 'thing',
        fetcher: fetcher,
      );

      expect(
        const ResourceChangedEvent(null, model: 'thing').isAbout(api),
        isTrue,
      );
      expect(
        const ResourceChangedEvent(null, model: 'other').isAbout(api),
        isFalse,
      );
    });

    test('falls back on the path when the event names no model', () {
      final api = _ThingApi('/things', fetcher: fetcher);

      expect(const ResourceChangedEvent('/things').isAbout(api), isTrue);
      expect(const ResourceChangedEvent('/others').isAbout(api), isFalse);
    });

    test('never compares a named event by path', () {
      final unresolved = _ThingApi(
        '/{workspace}',
        modelName: 'flow',
        fetcher: fetcher,
      );

      expect(
        const ResourceChangedEvent(
          '/{workspace}',
          model: 'notification',
        ).isAbout(unresolved),
        isFalse,
      );
    });
  });

  group('mayBeAbout', () {
    test('matches a carried column as a string', () {
      const event = ResourceChangedEvent(null, data: {'flow': 42});

      expect(event.mayBeAbout({'flow': '42'}), isTrue);
      expect(event.mayBeAbout({'flow': 7}), isFalse);
    });

    test(
      'says nothing for a column not carried, carried empty, or no data',
      () {
        expect(
          const ResourceChangedEvent(
            null,
            data: {'flow': null},
          ).mayBeAbout({'flow': 7}),
          isTrue,
        );
        expect(
          const ResourceChangedEvent(null, data: {}).mayBeAbout({'flow': 7}),
          isTrue,
        );
        expect(
          const ResourceChangedEvent(null).mayBeAbout({'flow': 7}),
          isTrue,
        );
      },
    );
  });

  group('touches', () {
    test('counts extra for every custom field read, and one for extra', () {
      expect(
        const ResourceChangedEvent(
          null,
          type: ResourceChangeType.updated,
          fields: {'extra', 'updated_at'},
        ).touches(['extra_priority']),
        isTrue,
      );
      expect(
        const ResourceChangedEvent(
          null,
          type: ResourceChangeType.updated,
          fields: {'extra_priority'},
        ).touches(['extra']),
        isTrue,
      );
    });

    test('keeps two custom fields apart', () {
      expect(
        const ResourceChangedEvent(
          null,
          type: ResourceChangeType.updated,
          fields: {'extra_priority'},
        ).touches(['extra_color']),
        isFalse,
      );
    });
  });

  test('travels with its model and origin, and without a path', () {
    const event = ResourceChangedEvent(
      null,
      model: 'flow',
      type: ResourceChangeType.updated,
      id: 7,
      origin: 'sibling',
    );

    final back = ResourceChangedEvent.fromJson(event.toJson(), relayed: true);

    expect(back.basePath, isNull);
    expect(back.model, 'flow');
    expect(back.id, 7);
    expect(back.origin, 'sibling');
    expect(back.relayed, isTrue);
  });

  test('travels with the scope it comes from', () {
    const event = ResourceChangedEvent(
      null,
      model: 'flow',
      type: ResourceChangeType.updated,
      id: 7,
      scopeId: 12,
    );

    expect(ResourceChangedEvent.fromJson(event.toJson()).scopeId, 12);
  });
}
