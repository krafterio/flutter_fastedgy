/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async';

import 'package:flutter_fastedgy/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart'
    show container, hasService;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

/// The shapes the card asked for, in the order it asked.
///
/// A spec is what the module hands over; what it looks like is the
/// application's, so the harness records the ask rather than measuring a widget.
final _asked = <RichTextPlaceholderSpec>[];

void main() {
  setUp(setUpUiTestServices);
  tearDown(resetUiTestServices);

  /// A source whose card arrives only when the test says so.
  late Completer<MentionPreview?> reading;

  MentionSource sourceOf(
    String model,
    MentionPreviewShape shape, {
    bool reads = true,
  }) => MentionSource(
    trigger: '@',
    model: model,
    getLabel: () => 'Mention',
    icon: Icons.alternate_email,
    search: (query, options) async => const [],
    previewShape: shape,
    preview: reads ? (id) => reading.future : null,
  );

  Future<void> open(WidgetTester tester, MentionSource source) async {
    reading = Completer<MentionPreview?>();
    _asked.clear();

    if (hasService<MentionSources>()) {
      await container.unregister<MentionSources>();
    }

    container.registerSingleton<MentionSources>(MentionSources([source]));

    late BuildContext anchor;

    await tester.pumpWidget(
      ComponentTheme<RichTextControls>(
        data: RichTextControls.fallback.copyWith(
          placeholder: (context, spec) {
            _asked.add(spec);

            return SizedBox(width: spec.width, height: spec.height);
          },
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                anchor = context;

                return const SizedBox(width: 120, height: 24);
              },
            ),
          ),
        ),
      ),
    );

    showMentionPopover(
      anchor,
      Mention(
        address: MentionAddress(
          model: source.model,
          id: 3,
          uri: Uri.parse('/r/${source.model}/3'),
        ),
        label: '@François Pluchino',
      ),
    );
    await tester.pump();
  }

  group('the card of a mention while its record is read', () {
    testWidgets('does not say the name before the rest of the card', (
      tester,
    ) async {
      await open(
        tester,
        sourceOf(
          'user',
          const MentionPreviewShape(
            leading: MentionLeading.avatar,
            subtitle: true,
          ),
        ),
      );

      // The label is known from the text, and showing it at full size beside a
      // skeleton read as a card half-arrived — then jumped when the real name
      // landed under it.
      expect(find.text('@François Pluchino'), findsNothing);
    });

    testWidgets('stands in for a face, a name and the line under it', (
      tester,
    ) async {
      await open(
        tester,
        sourceOf(
          'user',
          const MentionPreviewShape(
            leading: MentionLeading.avatar,
            subtitle: true,
          ),
        ),
      );

      expect(_asked, hasLength(3));
      // Round and twice the size of a glyph: a member's card leads with a face.
      // Looked up rather than taken first: a leading widget builds after the
      // siblings whose build asked for theirs.
      final face = _asked.singleWhere((shape) => shape.radius != null);

      expect(face.width, 32);
      expect(face.height, 32);
      expect(face.radius?.topLeft.x, 16);
    });

    testWidgets('stands in for as many facts as the card will hold', (
      tester,
    ) async {
      await open(
        tester,
        sourceOf(
          'record',
          const MentionPreviewShape(
            leading: MentionLeading.icon,
            subtitle: true,
            facts: 3,
          ),
        ),
      );

      // A glyph, the name, the line under it, and a label and a value per fact.
      expect(_asked, hasLength(3 + 3 * 2));
      expect(_asked.singleWhere((shape) => shape.radius != null).width, 16);
    });

    testWidgets('stands in for a name even where the kind declares no shape', (
      tester,
    ) async {
      await open(tester, sourceOf('user', MentionPreviewShape.none));

      // Something is on its way, so the card says so — never the label at full
      // size, whatever the kind of mention.
      expect(_asked, hasLength(1));
      expect(find.text('@François Pluchino'), findsNothing);
    });

    testWidgets('stands in for nothing at all where there is no card to come', (
      tester,
    ) async {
      await open(
        tester,
        sourceOf('user', MentionPreviewShape.none, reads: false),
      );

      // Nothing to wait for: the label is all this mention will ever say, and
      // a skeleton would promise something that is not coming.
      expect(_asked, isEmpty);
      expect(find.text('@François Pluchino'), findsOneWidget);
    });

    testWidgets('gives way to the record once it has arrived', (tester) async {
      await open(
        tester,
        sourceOf(
          'user',
          const MentionPreviewShape(
            leading: MentionLeading.avatar,
            subtitle: true,
          ),
        ),
      );

      expect(_asked, isNotEmpty);

      reading.complete(
        const MentionPreview(
          title: 'François Pluchino',
          subtitle: 'francois@krafter.io',
        ),
      );
      // What the next frame asks for, not what every frame has asked so far.
      _asked.clear();
      await tester.pump();

      expect(_asked, isEmpty);
      expect(find.text('francois@krafter.io'), findsOneWidget);
    });

    testWidgets('stops standing in when the record turns out to be gone', (
      tester,
    ) async {
      await open(
        tester,
        sourceOf(
          'user',
          const MentionPreviewShape(
            leading: MentionLeading.avatar,
            subtitle: true,
          ),
        ),
      );

      reading.complete(null);
      _asked.clear();
      await tester.pump();

      // Nothing to say beyond what the document said, and no skeleton left
      // promising something on its way.
      expect(_asked, isEmpty);
      expect(find.text('@François Pluchino'), findsOneWidget);
    });
  });
}
