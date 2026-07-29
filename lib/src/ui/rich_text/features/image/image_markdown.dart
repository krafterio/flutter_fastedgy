/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// The size a picture was given, carried in its own marker.
///
/// Markdown says nothing of how big an image is drawn, so a resized picture
/// came back at full width on the next read. The scheme is ours, so the size
/// rides along in it — `attachment:15?w=420&h=280` — and never reaches a
/// server as anything but part of the reference.
const _sizeSeparator = '?';

/// Writes an image as a block of its own, with the size it was given.
///
/// The package's parser emits `![](url)` and nothing more, so the next block
/// begins on the very next line — markdown then reads the picture as part of
/// that paragraph, and the decoder, which only makes a block of an image that
/// stands alone, drops it. The image survived until the first reload.
class StandaloneImageNodeParser extends NodeParser {
  const StandaloneImageNodeParser();

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final url = node.attributes[ImageBlockKeys.url];
    final opensOnBlankLine =
        node.previous != null && node.parent?.type == PageBlockKeys.type;

    return '${opensOnBlankLine ? '\n' : ''}![]($url${_size(node)})\n\n';
  }

  String _size(Node node) {
    final width = (node.attributes[ImageBlockKeys.width] as num?)?.round();
    final height = (node.attributes[ImageBlockKeys.height] as num?)?.round();

    if (width == null) {
      return '';
    }

    return '$_sizeSeparator w=$width${height == null ? '' : '&h=$height'}'
        .replaceAll(' ', '');
  }
}

/// Reads an image back, size included.
///
/// Ahead of the package's own parser, which keeps the source verbatim and would
/// leave the size sitting inside the address.
class SizedImageParser extends CustomMarkdownParser {
  const SizedImageParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    final src = _sourceOf(element);

    if (src == null) {
      return [];
    }

    final cut = src.indexOf(_sizeSeparator);

    if (cut < 0) {
      return [imageNode(url: src)];
    }

    final size = Uri.splitQueryString(src.substring(cut + 1));

    return [
      imageNode(
        url: src.substring(0, cut),
        width: double.tryParse(size['w'] ?? ''),
        height: double.tryParse(size['h'] ?? ''),
      ),
    ];
  }

  String? _sourceOf(md.Node element) {
    if (element is! md.Element) {
      return null;
    }

    if (element.attributes['src'] != null) {
      return element.attributes['src'];
    }

    final children = element.children;

    if (children == null || children.length != 1) {
      return null;
    }

    final child = children.first;

    return child is md.Element && child.tag == 'img'
        ? child.attributes['src']
        : null;
  }
}
