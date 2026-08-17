/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter_fastedgy/ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart'
    show
        CachedApiImage,
        Fetcher,
        StorageDownloader,
        container,
        getService,
        hasService;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ui_setup.dart';

/// A one-pixel PNG, the smallest thing a paste can carry.
const _pixel =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  setUp(() {
    setUpUiTestServices();

    // Only this suite resolves an attachment's URL. Registering it for every
    // test would make the ones merely showing a picture download it for real.
    if (!hasService<StorageDownloader>()) {
      container.registerSingleton<StorageDownloader>(
        StorageDownloader(getService<Fetcher>()),
      );
    }
  });
  tearDown(resetUiTestServices);

  /// The override has to be undone before the body returns — the framework
  /// checks the foundation's debug flags there, so a tear-down would be too
  /// late and the failure would name the wrong thing.
  Future<void> on(TargetPlatform platform, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;

    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('where an image points', () {
    test('an attachment is read back from its reference', () {
      expect(attachmentIdOf('attachment:42'), 42);
      expect(attachmentImageUrl(42), 'attachment:42');
    });

    test('anything else is not an attachment', () {
      expect(attachmentIdOf(null), isNull);
      expect(attachmentIdOf('https://example.org/a.png'), isNull);
      expect(attachmentIdOf('attachment:'), isNull);
      expect(attachmentIdOf('attachment:abc'), isNull);
      expect(attachmentIdOf(_pixel), isNull);
    });

    test('a data image gives up its bytes, and nothing else does', () {
      expect(inlineImageBytes(_pixel), isNotNull);
      expect(inlineImageBytes(_pixel), isNotEmpty);
      expect(inlineImageBytes('attachment:42'), isNull);
      expect(inlineImageBytes('data:image/png,notbase64'), isNull);
      expect(inlineImageBytes(null), isNull);
    });
  });

  group('through markdown', () {
    const codec = MarkdownRichTextCodec(features: defaultRichTextFeatures);

    Document documentOf(List<Node> nodes) =>
        Document.blank()..insert([0], nodes);

    test('an attachment reference travels untouched', () {
      final markdown = codec.encode(
        documentOf([imageNode(url: attachmentImageUrl(42))]),
      );

      expect(markdown, '![](attachment:42)');

      final blocks = codec.decode(markdown).root.children;

      expect(blocks.single.type, ImageBlockKeys.type);
      expect(
        attachmentIdOf(blocks.single.attributes[ImageBlockKeys.url] as String?),
        42,
      );
    });

    test('an image stands on its own, whatever follows it', () {
      // Written with no blank line after it, the picture reads as part of the
      // next paragraph and the decoder drops it: the image survived until the
      // first reload, then vanished.
      final markdown = codec.encode(
        documentOf([
          imageNode(url: attachmentImageUrl(15)),
          paragraphNode(delta: Delta()..insert('Après')),
        ]),
      );

      final blocks = codec.decode(markdown).root.children;

      expect(blocks.map((block) => block.type), [
        ImageBlockKeys.type,
        'paragraph',
      ]);
      expect(
        attachmentIdOf(blocks.first.attributes[ImageBlockKeys.url] as String?),
        15,
      );
    });

    test('and between two paragraphs', () {
      final blocks = codec
          .decode(
            codec.encode(
              documentOf([
                paragraphNode(delta: Delta()..insert('Avant')),
                imageNode(url: attachmentImageUrl(15)),
                paragraphNode(delta: Delta()..insert('Après')),
              ]),
            ),
          )
          .root
          .children;

      expect(blocks.map((block) => block.type), [
        'paragraph',
        ImageBlockKeys.type,
        'paragraph',
      ]);
    });

    test('the size a picture was given survives the round trip', () {
      // Markdown says nothing of how big an image is drawn, so a resized
      // picture came back at full width on the next read.
      final markdown = codec.encode(
        documentOf([
          imageNode(url: attachmentImageUrl(15), width: 420, height: 280),
        ]),
      );

      expect(markdown, contains('w=420'));

      final block = codec.decode(markdown).root.children.single;

      expect(block.attributes[ImageBlockKeys.width], 420);
      expect(block.attributes[ImageBlockKeys.height], 280);
      // The size rides in the marker, never in the reference itself.
      expect(
        attachmentIdOf(block.attributes[ImageBlockKeys.url] as String?),
        15,
      );
    });

    test('a picture never resized carries no size', () {
      final markdown = codec.encode(
        documentOf([imageNode(url: attachmentImageUrl(15))]),
      );

      expect(markdown.trim(), '![](attachment:15)');
    });

    test(
      'an image inserted offline survives as it was, until a save stores it',
      () {
        // The data URI is what an offline insert leaves behind; losing it in the
        // round trip would lose the picture before it ever reached the server.
        final blocks = codec
            .decode(codec.encode(documentOf([imageNode(url: _pixel)])))
            .root
            .children;

        expect(
          inlineImageBytes(
            blocks.single.attributes[ImageBlockKeys.url] as String?,
          ),
          isNotNull,
        );
      },
    );
  });

  group('the handle to resize a picture', () {
    /// Sized on the block rather than left to the picture: a test image never
    /// decodes within a pump, so its own height would be zero and there would
    /// be nothing to hover over.
    Future<void> pump(WidgetTester tester, {bool reading = false}) async {
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [imageNode(url: _pixel, width: 200, height: 120)]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: reading
                ? RichTextViewer(
                    editorState: state,
                    features: defaultRichTextFeatures,
                  )
                : RichTextEditor(
                    features: defaultRichTextFeatures,
                    editorState: state,
                  ),
          ),
        ),
      );
      await tester.pump();
    }

    /// The handle names itself by the cursor it wears; nothing else does.
    final handle = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.cursor == SystemMouseCursors.resizeLeftRight,
    );

    Future<TestGesture> pointAt(WidgetTester tester, Finder target) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();

      return gesture;
    }

    testWidgets('waits to be hovered rather than standing over the picture', (
      tester,
    ) async {
      await on(TargetPlatform.macOS, () async {
        await pump(tester);

        expect(handle, findsNothing);

        await pointAt(tester, find.byType(Image));

        expect(handle, findsOneWidget);
      });
    });

    testWidgets('goes again once the pointer leaves', (tester) async {
      await on(TargetPlatform.macOS, () async {
        await pump(tester);

        final gesture = await pointAt(tester, find.byType(Image));

        expect(handle, findsOneWidget);

        await gesture.moveTo(const Offset(-100, -100));
        await tester.pump();

        expect(handle, findsNothing);
      });
    });

    testWidgets('stands there where nothing can hover', (tester) async {
      await on(TargetPlatform.iOS, () async {
        await pump(tester);

        // A touch screen has no pointer to reveal it with, and a handle that
        // never appears is a picture that cannot be resized.
        expect(handle, findsOneWidget);
      });
    });

    testWidgets('never shows itself to a reader, hovered or not', (
      tester,
    ) async {
      await on(TargetPlatform.macOS, () async {
        await pump(tester, reading: true);
        await pointAt(tester, find.byType(Image));

        expect(handle, findsNothing);
      });
    });

    testWidgets('offre au doigt de quoi se poser dessus', (tester) async {
      late double pointer;

      await on(TargetPlatform.macOS, () async {
        await pump(tester);
        await pointAt(tester, find.byType(Image));
        pointer = tester.getSize(handle).width;
      });

      await on(TargetPlatform.iOS, () async {
        await pump(tester);

        // La barre dessinée ne change pas ; c'est la zone autour qui grandit.
        expect(tester.getSize(handle).width, greaterThan(pointer));
      });
    });

    testWidgets('un glissement au doigt redimensionne vraiment', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = EditorState(
          document: Document.blank()
            ..insert([0], [imageNode(url: _pixel, width: 200, height: 120)]),
        );
        addTearDown(state.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
              ),
            ),
          ),
        );
        await tester.pump();

        // Sans arbitrage : la poignée est posée sur un éditeur qui prend le
        // premier contact pour une sélection, et dans une page qui défile.
        await tester.drag(handle, const Offset(-60, 0));
        await tester.pumpAndSettle();

        final width =
            (state.getNodeAtPath([0])?.attributes[ImageBlockKeys.width] as num?)
                ?.toDouble();

        expect(width, isNotNull);
        expect(width, lessThan(200));
      });
    });

    testWidgets('a tap without a drag selects the picture', (tester) async {
      await on(TargetPlatform.iOS, () async {
        final state = EditorState(
          document: Document.blank()
            ..insert([0], [imageNode(url: _pixel, width: 200, height: 120)]),
        );
        addTearDown(state.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(handle);
        await tester.pumpAndSettle();

        expect(
          state.selection,
          Selection.single(path: [0], startOffset: 0, endOffset: 1),
        );
        expect(
          (state.getNodeAtPath([0])?.attributes[ImageBlockKeys.width] as num?)
              ?.toDouble(),
          200,
        );
      });
    });
  });

  group('tapping beside a picture', () {
    Future<EditorState> pump(WidgetTester tester) async {
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [imageNode(url: _pixel, width: 200, height: 120)]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
            ),
          ),
        ),
      );
      await tester.pump();

      return state;
    }

    List<String> blocksOf(EditorState state) => [
      for (final node in state.document.root.children) node.type,
    ];

    testWidgets('on its right the caret lands in the paragraph it adds', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = await pump(tester);
        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(Offset(picture.right + 120, picture.center.dy));
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ImageBlockKeys.type, ParagraphBlockKeys.type]);
        expect(
          state.selection,
          Selection.collapsed(Position(path: [1], offset: 0)),
        );
      });
    });

    testWidgets('on the edge of the picture it lands before it', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = await pump(tester);
        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(Offset(picture.left + 4, picture.center.dy));
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ParagraphBlockKeys.type, ImageBlockKeys.type]);
        expect(
          state.selection,
          Selection.collapsed(Position(path: [0], offset: 0)),
        );

        // Over the picture the line is as provisional as the one under it, and
        // taking it back moves everything that followed it back up a path.
        state.selection = Selection.single(
          path: [1],
          startOffset: 0,
          endOffset: 1,
        );
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ImageBlockKeys.type]);
        expect(
          state.selection,
          Selection.single(path: [0], startOffset: 0, endOffset: 1),
        );
      });
    });

    testWidgets('under the last block the caret lands after it', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = await pump(tester);
        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(Offset(picture.center.dx, picture.bottom + 200));
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ImageBlockKeys.type, ParagraphBlockKeys.type]);
        expect(
          state.selection,
          Selection.collapsed(Position(path: [1], offset: 0)),
        );
      });
    });

    testWidgets('the text already written beside it is left alone', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = EditorState(
          document: Document.blank()
            ..insert(
              [0],
              [
                imageNode(url: _pixel, width: 200, height: 120),
                paragraphNode(delta: Delta()..insert('After')),
              ],
            ),
        );
        addTearDown(state.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
              ),
            ),
          ),
        );
        await tester.pump();

        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(Offset(picture.right + 120, picture.center.dy));
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ImageBlockKeys.type, ParagraphBlockKeys.type]);
        expect(
          state.selection,
          Selection.collapsed(Position(path: [1], offset: 0)),
        );
      });
    });

    testWidgets('the line it adds goes again when the caret leaves it', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = EditorState(
          document: Document.blank()
            ..insert(
              [0],
              [
                paragraphNode(delta: Delta()..insert('Before')),
                imageNode(url: _pixel, width: 200, height: 120),
              ],
            ),
        );
        addTearDown(state.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RichTextEditor(
                features: defaultRichTextFeatures,
                editorState: state,
              ),
            ),
          ),
        );
        await tester.pump();

        final written = const MarkdownRichTextCodec(
          features: defaultRichTextFeatures,
        ).encode(state.document);
        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(Offset(picture.right + 120, picture.center.dy));
        await tester.pumpAndSettle();

        expect(blocksOf(state), [
          ParagraphBlockKeys.type,
          ImageBlockKeys.type,
          ParagraphBlockKeys.type,
        ]);

        state.selection = Selection.collapsed(Position(path: [0], offset: 6));
        await tester.pumpAndSettle();

        // Nothing was written in it, so nothing was written at all: the
        // document is back to what a save would have found before the tap.
        expect(blocksOf(state), [ParagraphBlockKeys.type, ImageBlockKeys.type]);
        expect(
          state.selection,
          Selection.collapsed(Position(path: [0], offset: 6)),
        );
        expect(
          const MarkdownRichTextCodec(
            features: defaultRichTextFeatures,
          ).encode(state.document),
          written,
        );
      });
    });

    testWidgets('the line it adds stays once something is written in it', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = await pump(tester);
        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(Offset(picture.right + 120, picture.center.dy));
        await tester.pumpAndSettle();

        await state.insertTextAtPosition(
          'Written',
          position: Position(path: [1], offset: 0),
        );
        await tester.pumpAndSettle();

        state.selection = Selection.collapsed(Position(path: [0], offset: 0));
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ImageBlockKeys.type, ParagraphBlockKeys.type]);
        expect(state.getNodeAtPath([1])?.delta?.toPlainText(), 'Written');
      });
    });

    testWidgets('the middle of the picture still opens the gallery', (
      tester,
    ) async {
      await on(TargetPlatform.iOS, () async {
        final state = await pump(tester);
        final picture = tester.getRect(find.byType(Image));

        await tester.tapAt(picture.center);
        await tester.pumpAndSettle();

        expect(blocksOf(state), [ImageBlockKeys.type]);
      });
    });
  });

  group('the caret around a picture', () {
    /// A picture between two paragraphs, mounted so each block has a selectable
    /// of its own — which is what the commands walk through.
    Future<EditorState> pump(WidgetTester tester) async {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [
              paragraphNode(delta: Delta()..insert('Avant')),
              imageNode(url: _pixel),
              paragraphNode(delta: Delta()..insert('Après')),
            ],
          ),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
            ),
          ),
        ),
      );
      await tester.pump();

      return state;
    }

    KeyEventResult press(EditorState state, CommandShortcutEvent command) =>
        command.handler(state);

    testWidgets('walks out of it to the right, into the text beyond', (
      tester,
    ) async {
      // The report that made this a test: the package moves a caret sideways by
      // walking the block's delta, and a picture has none — so the caret
      // reached the picture and stayed on it, while up and down still worked.
      final state = await pump(tester);
      state.selection = Selection.collapsed(Position(path: [1], offset: 0));

      expect(press(state, stepRightCommand), KeyEventResult.handled);
      expect(
        state.selection,
        Selection.collapsed(Position(path: [2], offset: 0)),
      );
    });

    testWidgets('walks out of it to the left, back into the text before', (
      tester,
    ) async {
      final state = await pump(tester);
      state.selection = Selection.collapsed(Position(path: [1], offset: 1));

      expect(press(state, stepLeftCommand), KeyEventResult.handled);
      expect(
        state.selection,
        Selection.collapsed(Position(path: [0], offset: 5)),
      );
    });

    testWidgets('does what the package on its own cannot', (tester) async {
      final state = await pump(tester);
      final onThePicture = Position(path: [1], offset: 0);

      // Walking the block's delta is how the package moves a caret sideways.
      // A picture has none, so it hands back the position it was given — the
      // caret was stuck on the picture, and this is why. Its `forward` means
      // leftward, so the second line is the direction that still worked: from
      // the near edge, back into the words before.
      expect(onThePicture.moveHorizontal(state, forward: false), onThePicture);
      expect(
        onThePicture.moveHorizontal(state, forward: true),
        isNot(onThePicture),
      );
    });

    test(
      'are the editor\'s own, so a picture is stepped over wherever it is',
      () {
        // They were the image feature's, and a table needs the very same thing:
        // the package walks a delta to move a caret, and neither block has one.
        expect(
          wholeBlockCommands,
          containsAll([stepLeftCommand, stepRightCommand]),
        );
      },
    );

    testWidgets('leaves a caret in the text to the package', (tester) async {
      final state = await pump(tester);
      state.selection = Selection.collapsed(Position(path: [0], offset: 2));

      // Taking the key here would break the movement the package gets right.
      expect(press(state, stepRightCommand), KeyEventResult.ignored);
      expect(press(state, stepLeftCommand), KeyEventResult.ignored);
      expect(
        state.selection,
        Selection.collapsed(Position(path: [0], offset: 2)),
      );
    });

    testWidgets('stays put on a picture with nothing beyond it', (
      tester,
    ) async {
      final state = EditorState(
        document: Document.blank()..insert([0], [imageNode(url: _pixel)]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              features: defaultRichTextFeatures,
              editorState: state,
            ),
          ),
        ),
      );
      await tester.pump();

      state.selection = Selection.collapsed(Position(path: [0], offset: 0));

      expect(press(state, stepRightCommand), KeyEventResult.ignored);
      expect(press(state, stepLeftCommand), KeyEventResult.ignored);
    });
  });

  group('rendered', () {
    Future<void> pump(WidgetTester tester, String url) async {
      final state = EditorState(
        document: Document.blank()..insert([0], [imageNode(url: url)]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextViewer(
              editorState: state,
              features: defaultRichTextFeatures,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    test('an attachment is addressed by its storage path, not by a URL', () {
      final path = attachmentDownloadPath(42);

      expect(path, 'attachments/42');
      // A finished URL made the image layer build one on top of another, and
      // the request 404'd on a doubled path.
      expect(path, isNot(startsWith('/')));
      expect(path, isNot(contains('storage/download')));
      expect(path, isNot(contains('?')));
    });

    testWidgets(
      'a data image is shown from its own bytes, no download at all',
      (tester) async {
        await pump(tester, _pixel);

        expect(find.byType(CachedApiImage), findsNothing);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'a picture with no size of its own fills the width, its height following',
      (tester) async {
        // What a squeezed picture looked like: capped short, and the width it
        // could not use showing as a margin down the right-hand side.
        await pump(tester, _pixel);

        final column = tester.getSize(find.byType(RichTextViewer)).width;
        final drawn = tester.widget<Image>(find.byType(Image));

        expect(drawn.width, column);
        // No height asked of it at all: the picture's own shape sets it. A cap
        // here is what squeezed a tall screenshot into a short box.
        expect(drawn.height, isNull);
      },
    );

    testWidgets('a resized picture keeps its shape when the window narrows it', (
      tester,
    ) async {
      // The size it was left at, shown in a column half as wide: the picture is
      // forced down to the column, and the box has to come down with it. Held
      // to the stored height it stayed as tall as it ever was, and the picture
      // sat in a frame far too big for it.
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [imageNode(url: _pixel, width: 400, height: 200)]),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: RichTextViewer(
                editorState: state,
                features: defaultRichTextFeatures,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final drawn = tester.getSize(find.byType(Image));

      expect(drawn.width, 200);
      expect(drawn.height, 100);
    });

    testWidgets('no handle to drag while it is only being read', (
      tester,
    ) async {
      await pump(tester, _pixel);

      // The picture still answers a tap — that opens the gallery, and a reader
      // wants it too. What reading has no use for is the resize handle.
      final cursors = tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .map((region) => region.cursor);

      expect(cursors, isNot(contains(SystemMouseCursors.resizeLeftRight)));
    });
  });

  group('in the "/" menu', () {
    test('ours stands in for the package entry rather than beside it', () {
      final items = richTextSlashMenuItems(
        defaultRichTextFeatures,
      ).where((item) => item.name == t('Image'));

      expect(items, hasLength(1));
      // The package's own would open its untranslated dialog on the block we
      // replaced, so it must be gone, not merely outnumbered.
      expect(defaultRichTextFeatures.replacedMenuItems, contains('Image'));
    });

    test('narrowing the features gives the package entry back', () {
      final bare = defaultRichTextFeatures.without<ImageFeature>();
      final items = richTextSlashMenuItems(
        bare,
      ).where((item) => item.name == t('Image'));

      expect(items, hasLength(1));
      expect(bare.replacedMenuItems, isNot(contains('Image')));
    });
  });

  group('inserting', () {
    EditorState stateOf(List<Node> nodes) {
      final state = EditorState(document: Document.blank()..insert([0], nodes));
      addTearDown(state.dispose);

      return state;
    }

    test(
      'takes the place of the empty block the "/" menu left behind',
      () async {
        final state = stateOf([
          paragraphNode(delta: Delta()..insert('Avant')),
          paragraphNode(),
        ]);

        await insertImage(
          state,
          Selection.collapsed(Position(path: [1])),
          attachmentImageUrl(7),
        );

        final blocks = state.document.root.children;

        // No blank line under the picture: the empty paragraph became it.
        expect(blocks.map((block) => block.type), [
          'paragraph',
          ImageBlockKeys.type,
        ]);
        expect(
          blocks.last.attributes[ImageBlockKeys.url],
          attachmentImageUrl(7),
        );
      },
    );

    test('goes after a block that holds something', () async {
      final state = stateOf([
        paragraphNode(delta: Delta()..insert('Un texte')),
      ]);

      await insertImage(
        state,
        Selection.collapsed(Position(path: [0])),
        attachmentImageUrl(7),
      );

      final blocks = state.document.root.children;

      expect(blocks.map((block) => block.type), [
        'paragraph',
        ImageBlockKeys.type,
      ]);
      expect(blocks.first.delta?.toPlainText(), 'Un texte');
    });
  });

  group('while an attachment is on its way', () {
    testWidgets('the block holds a shape, never a spinner', (tester) async {
      final state = EditorState(
        document: Document.blank()
          ..insert(
            [0],
            [imageNode(url: 'attachment:42', width: 200, height: 120)],
          ),
      );
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextViewer(
              editorState: state,
              features: defaultRichTextFeatures,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // The shape it was stored at, so the page does not move when the bytes
      // land: 200 by 120 is the same ratio as the box the placeholder takes.
      final box = tester.getSize(
        find
            .descendant(
              of: find.byType(CachedApiImage),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(box.width / box.height, closeTo(200 / 120, 0.01));

      // The download it started outlives the tree unless it is let go of.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
  });
}
