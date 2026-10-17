/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the card the way the "/" entry does, and hands back the context it was
/// opened from so a test can assert on what it drew.
Future<EditorState> _open(
  WidgetTester tester, {
  ImageFilePicker? pickFile,
  ImageBytesPicker? pickImage,
  ImageBytesStore? storeImage,
}) async {
  final state = EditorState(
    document: Document.blank()..insert([0], [paragraphNode(text: 'Une ligne')]),
  );
  addTearDown(state.dispose);

  late BuildContext anchor;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            anchor = context;

            return RichTextEditor(
              editorState: state,
              features: const RichTextFeatures([]),
            );
          },
        ),
      ),
    ),
  );

  state.selection = Selection.collapsed(Position(path: const [0], offset: 0));
  await tester.pumpAndSettle();

  showImageEditor(
    anchor,
    state,
    state.selection!,
    pickFile: pickFile,
    pickImage: pickImage,
    storeImage: storeImage,
  );
  await tester.pumpAndSettle();

  return state;
}

/// The address of the first picture of [state]'s document.
String? _pictureOf(EditorState state) =>
    state.document.root.children
            .where((node) => node.type == ImageBlockKeys.type)
            .firstOrNull
            ?.attributes[ImageBlockKeys.url]
        as String?;

final _photo = PickedImage(
  bytes: Uint8List.fromList([1, 2, 3]),
  name: 'photo.png',
);

void main() {
  group('showImageEditor', () {
    testWidgets('offers this device when the application supplies a picker', (
      tester,
    ) async {
      await _open(tester, pickFile: () async => File('nowhere.png'));

      expect(find.text('Choose an image'), findsOneWidget);
    });

    testWidgets('offers this device when the picker reads bytes', (
      tester,
    ) async {
      await _open(tester, pickImage: () async => _photo);

      expect(find.text('Choose an image'), findsOneWidget);
    });

    testWidgets(
      'a picture picked as its bytes lands as the attachment it was stored as',
      (tester) async {
        PickedImage? stored;
        final state = await _open(
          tester,
          pickImage: () async => _photo,
          storeImage: (image) async {
            stored = image;

            return 42;
          },
        );

        await tester.tap(find.text('Choose an image'));
        await tester.pumpAndSettle();

        expect(stored, same(_photo));
        expect(_pictureOf(state), 'attachment:42');
      },
    );

    testWidgets(
      'a picture picked as its bytes with nowhere to store it lands inline',
      (tester) async {
        final state = await _open(tester, pickImage: () async => _photo);

        await tester.tap(find.text('Choose an image'));
        await tester.pumpAndSettle();

        expect(_pictureOf(state), 'data:image/png;base64,AQID');
      },
    );

    testWidgets('offers an address alone when it does not', (tester) async {
      await _open(tester);

      // Never a button that opens nothing: an application with no file plugin
      // gets the half of the card that works, not a dead half beside it.
      expect(find.text('Choose an image'), findsNothing);
      expect(find.text('Paste an image address'), findsOneWidget);
    });
  });
}
