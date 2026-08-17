/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../../rich_text_action.dart';
import '../../rich_text_feature.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;

import '../../../icons.dart';
import 'image_component.dart';
import 'image_markdown.dart';
import 'image_menu.dart';

/// Images in a document, stored as attachments of the record rather than
/// carried inside its text.
///
/// Replaces the package's block, which renders an image straight from its
/// `src`, and the package's "/" entry, which opens an untranslated dialog of
/// its own and leaves a data URI behind.
///
/// The markdown needs no teaching: the package writes `![](src)` and reads the
/// `src` back verbatim, so `attachment:42` travels on its own. A `data:` image
/// survives the same way, which is what carries a picture inserted offline
/// until a save turns it into an attachment.
class ImageFeature extends RichTextFeature {
  /// How a picked image becomes an attachment. Without it — a document with no
  /// record behind it — the picture stays inline until something stores it.
  final ImageStore? store;

  /// Where a picture comes from on this device. Null leaves the card offering
  /// an address alone, which is what an application with no file plugin gets.
  final ImageFilePicker? pickFile;

  /// The glyph on the "/" menu entry — an argument for the reason every menu
  /// glyph is one: the editor builds that menu in an overlay of its own.
  final IconData menuIcon;

  const ImageFeature({
    this.store,
    this.pickFile,
    this.menuIcon = Icons.image_outlined,
  });

  @override
  Map<String, BlockComponentBuilder> get builders => {
    ImageBlockKeys.type: ImageComponentBuilder(),
  };

  @override
  List<NodeParser> get markdownEncoders => const [StandaloneImageNodeParser()];

  @override
  List<CustomMarkdownParser> get markdownDecoders => const [SizedImageParser()];

  @override
  Set<String> get replacesMenuItems => const {'Image'};

  /// Beside the blocks a button already turns the line into, because a picture
  /// is the one thing on the "/" menu somebody looks for on the strip: it is
  /// reached far more often than a rule, and on a phone the menu costs a
  /// character typed and a list read.
  @override
  List<RichTextAction> get actions => [
    RichTextAction(
      id: 'image',
      glyph: FastEdgyGlyph.image,
      getLabel: () => t('Image'),
      group: 3,
      isActive: (_) => false,
      isEnabled: (editorState) => editorState.selection != null,
      run: (editorState) async {
        final selection = editorState.selection;

        if (selection == null) {
          return;
        }

        // The block's own context, and not the one the strip was drawn with:
        // the card opens in the root overlay either way, and this one is sure
        // to be under the editor's themes.
        final context = editorState
            .getNodeAtPath(selection.start.path)
            ?.key
            .currentContext;

        if (context == null || !context.mounted) {
          return;
        }

        showImageEditor(
          context,
          editorState,
          selection,
          store: store,
          pickFile: pickFile,
        );
      },
    ),
  ];

  @override
  List<SelectionMenuItem> get menuItems => [
    SelectionMenuItem(
      getName: () => t('Image'),
      icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
        icon: menuIcon,
        isSelected: isSelected,
        style: style,
      ),
      keywords: ['image', 'picture', 'photo'],
      handler: (editorState, menuService, context) async {
        final selection = editorState.selection;

        if (selection == null) {
          return;
        }

        showImageEditor(
          context,
          editorState,
          selection,
          store: store,
          pickFile: pickFile,
        );
      },
    ),
  ];
}
