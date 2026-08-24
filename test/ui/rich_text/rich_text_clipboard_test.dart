/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    richTextClipboardHasContent.value = true;
  });

  RichTextAction pasteAction() =>
      RichTextActions.clipboard(defaultRichTextFeatures)
          .firstWhere((action) => action.id == 'paste');

  EditorState withCaret() {
    final state = EditorState(document: Document.blank(withInitialText: true))
      ..selection = Selection.collapsed(Position(path: [0], offset: 0));
    addTearDown(state.dispose);

    return state;
  }

  group('ce qu\'il y a à coller', () {
    test('le bouton ne s\'allume que quand le presse-papier dit oui', () {
      final state = withCaret();
      final paste = pasteAction();

      richTextClipboardHasContent.value = false;
      expect(paste.isEnabled(state), isFalse);

      richTextClipboardHasContent.value = true;
      expect(paste.isEnabled(state), isTrue);
    });

    test('et jamais sans curseur, même le presse-papier plein', () {
      final state = EditorState(
        document: Document.blank(withInitialText: true),
      );
      addTearDown(state.dispose);

      richTextClipboardHasContent.value = true;
      expect(pasteAction().isEnabled(state), isFalse);
    });

    test('la question posée est « y a-t-il », jamais « donne »', () async {
      final asked = <String>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            asked.add(call.method);

            return call.method == 'Clipboard.hasStrings'
                ? {'value': false}
                : null;
          });

      await refreshRichTextClipboard();

      // Demander le texte lèverait l'invite « Autoriser le collage ? » d'iOS à
      // chaque fois que la barre apparaît.
      expect(asked, ['Clipboard.hasStrings']);
      expect(richTextClipboardHasContent.value, isFalse);
    });

    test(
      'une plateforme qui refuse de répondre laisse le bouton vivant',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              throw PlatformException(code: 'nope');
            });

        richTextClipboardHasContent.value = false;
        await refreshRichTextClipboard();

        expect(richTextClipboardHasContent.value, isTrue);
      },
    );
  });

  group('le menu du clic droit', () {
    testWidgets('tient debout sans largeur imposée', (tester) async {
      final state = withCaret();

      // Ce qu'en fait l'éditeur : posé à un point d'un Stack, donc mesuré sans
      // aucune largeur. Une colonne étirée y valait l'infini.
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned(
                left: 10,
                top: 10,
                child: RichTextSurface(
                  child: RichTextClipboardMenu(
                    editorState: state,
                    actions: RichTextActions.clipboard(defaultRichTextFeatures),
                    direction: Axis.vertical,
                    onDone: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(RichTextSurface)).width,
        lessThanOrEqualTo(300.0),
      );
    });
  });
}
