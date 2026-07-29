/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show kPrecisePointerHitSlop, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:provider/provider.dart';

import '../../../icons.dart';
import '../../../interaction.dart';
import '../../../image/fullscreen_image_viewer.dart';
import '../../rich_text_caret.dart';
import '../../rich_text_controls.dart';
import '../../rich_text_theme.dart';
import 'image_source.dart';

/// The width the optimised variant is asked for, whatever width the image is
/// shown at.
/// One variant per image rather than one per size: shrinking a picture to a
/// fifth of the column must not fetch a fifth-sized file, or every drag of the
/// handle would download again and every enlargement would come back blurred.
const imageDownloadWidth = 720;

const _minWidth = 60.0;

const _handleWidth = 6.0;

/// The band along the picture's own edges where a tap asks for the caret before
/// or after it rather than for the picture itself.
const _edgeWidth = 24.0;

/// What holds the place while the bytes are on their way.
/// Only until then: a picture sizes itself once loaded, and it is the loading
/// state that asks for every pixel it can get — inside a column of blocks that
/// means an unbounded height, which does not lay out at all.
const _loadingHeight = 240.0;

/// The storage path an attached picture is read from.
/// A path, not a URL: the image layer composes the address and appends the size
/// it wants. Handing it a finished URL made it build one on top of another.
String attachmentDownloadPath(int id) => 'attachments/$id';

class ImageComponentBuilder extends BlockComponentBuilder {
  ImageComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;

    return ImageComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.attributes[ImageBlockKeys.url] is String;
}

/// An image in a document: the attachment it is stored as, downloaded through
/// the storage's optimisation and cache, and resizable while it is editable.
class ImageComponentWidget extends BlockComponentStatefulWidget {
  const ImageComponentWidget({
    required super.node,
    super.key,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ImageComponentWidget> createState() => _ImageComponentWidgetState();
}

class _ImageComponentWidgetState extends State<ImageComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  /// What the editor measures to draw a selection over the block, and what
  /// backspace needs to find: without it the picture cannot be selected, and so
  /// cannot be deleted.
  final _pictureKey = GlobalKey();

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  /// Set while a handle is held, so the picture follows the pointer without a
  /// transaction per frame.
  double? _dragging;

  bool _hovering = false;

  /// Whether the handle waits to be hovered rather than standing there.
  /// Only where there is a pointer to hover with: a touch screen has none, and
  /// a handle that never shows itself is a picture that cannot be resized.
  static bool get _hoverReveals => hasHoverPointer;

  /// Held through a drag: pulling the picture wider takes the pointer past its
  /// own edge, and a handle that vanished there would drop the drag with it.
  bool get _showsHandle => !_hoverReveals || _hovering || _dragging != null;

  String? get _url => node.attributes[ImageBlockKeys.url] as String?;

  double? get _storedWidth =>
      (node.attributes[ImageBlockKeys.width] as num?)?.toDouble();

  double? get _storedHeight =>
      (node.attributes[ImageBlockKeys.height] as num?)?.toDouble();

  /// The shape the picture was left in, rather than the height it was left at.
  /// A window narrower than the stored width forces the picture down, and a
  /// height held to what it once was leaves the box taller than what it draws —
  /// the picture shrinks, the frame around it does not.
  double? get _storedRatio {
    final width = _storedWidth;
    final height = _storedHeight;

    return width != null && height != null && height > 0
        ? width / height
        : null;
  }

  Future<void> _resize(double width, {double? height}) async {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction
      ..updateNode(node, {
        ImageBlockKeys.width: width,
        ImageBlockKeys.height: ?height,
      });

    await editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();

    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : imageDownloadWidth.toDouble();
        final width = (_dragging ?? _storedWidth ?? available).clamp(
          _minWidth,
          available,
        );

        return _picture(width, editable: editorState.editable);
      },
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }

    return child;
  }

  Widget _picture(double width, {required bool editable}) {
    // The height always follows the width through a ratio — the one measured
    // when a drag began, else the one the stored size describes. Letting it be
    // worked out anew each frame is what made the picture — and everything
    // under it — jump about during a drag; holding an absolute height is what
    // left the box frozen when the window resized the picture under it.
    final ratio = _ratio ?? _storedRatio;
    final height = ratio != null ? width / ratio : null;

    // No height of its own means the picture sets it: given a width and all the
    // height it asks for, the box it is drawn in takes the shape of the picture
    // itself. Capping it here is what used to squeeze a tall screenshot into a
    // short box and leave the width it could not use showing on the right.
    final Widget picture = height != null
        ? SizedBox(height: height, child: _image(width))
        : _image(width);

    // A picture holds no text, so a selection over it paints nothing of its
    // own. The veil is that paint: the very colour the editor lays over
    // selected text, so a picture caught in a selection reads like the words
    // around it, whether it was clicked or swept over.
    final image = ValueListenableBuilder<Selection?>(
      valueListenable: context.read<EditorState>().selectionNotifier,
      builder: (context, selection, child) => Stack(
        children: [
          child!,
          if (_isSelected(selection))
            Positioned.fill(
              // Never in the way of the resize handle underneath it.
              child: IgnorePointer(
                child: ColoredBox(
                  color: RichTextTheme.of(context).selectionVeil,
                ),
              ),
            ),
        ],
      ),
      child: picture,
    );

    final tappable = MouseRegion(
      cursor: SystemMouseCursors.click,
      // Lets the region around it see the pointer too: an opaque one absorbs
      // the mouse, and the picture would never know it was being hovered.
      opaque: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: editable
            ? (details) => _onPicture(details.localPosition, width)
            : (_) => _openGallery(),
        child: image,
      ),
    );

    if (!editable) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(key: _pictureKey, width: width, child: tappable),
      );
    }

    return Stack(
      children: [
        // Beside the picture the block is empty, and a tap there is asking for
        // the caret rather than for the picture.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_caret(forward: true)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          // Over the picture, not over the handle: the handle is what appears,
          // so it cannot be what is watched for.
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: SizedBox(
              key: _pictureKey,
              width: width,
              child: Stack(
                children: [
                  tappable,
                  if (_showsHandle)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: _Handle(
                        onDrag: (deltaX) => _drag(width, deltaX),
                        onTap: _select,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onPicture(Offset at, double width) {
    if (at.dx <= _edgeWidth) {
      unawaited(_caret(forward: false));

      return;
    }

    if (at.dx >= width - _edgeWidth) {
      unawaited(_caret(forward: true));

      return;
    }

    _openGallery();
  }

  /// Puts the caret in the block next to the picture, adding the paragraph it
  /// needs when the picture is the first or the last thing the document holds.
  Future<void> _caret({required bool forward}) async {
    final editorState = context.read<EditorState>();
    final node = widget.node;
    final neighbour = forward ? node.next : node.previous;
    final delta = neighbour?.delta;

    if (neighbour != null && delta != null) {
      editorState.updateSelectionWithReason(
        Selection.collapsed(
          Position(path: neighbour.path, offset: forward ? 0 : delta.length),
        ),
        reason: SelectionUpdateReason.uiEvent,
      );

      return;
    }

    await addParagraphForCaret(
      editorState,
      forward ? node.path.next : node.path,
    );
  }

  /// Every picture the document holds, in the order they are written.
  /// The gallery is of the document, not of the record: what is shown is what
  /// the reader is looking at, and a file merely attached to the flow has no
  /// place in it.
  List<Node> get _pictures => context
      .read<EditorState>()
      .document
      .root
      .children
      .where(
        (node) =>
            node.type == ImageBlockKeys.type &&
            attachmentIdOf(node.attributes[ImageBlockKeys.url] as String?) !=
                null,
      )
      .toList();

  void _openGallery() {
    final pictures = _pictures;
    final index = pictures.indexWhere(
      (picture) => picture.id == widget.node.id,
    );

    if (index < 0) {
      return;
    }

    final ids = [
      for (final picture in pictures)
        attachmentIdOf(picture.attributes[ImageBlockKeys.url] as String?)!,
    ];

    FullScreenImageViewer.show(
      context,
      images: [
        for (final id in ids)
          ViewerImage(
            path: attachmentDownloadPath(id),
            filename: _filenameOf(id),
          ),
      ],
      initialIndex: index,
      onSave: (at) => _download(ids[at]),
    );
  }

  /// A picture written into the text carries no name of its own — the file it
  /// is saved as takes the attachment it is stored as.
  String _filenameOf(int id) => 'image-$id.webp';

  Future<void> _download(int id) async {
    try {
      await StorageDownloadHelper.downloadAttachment(
        attachmentId: id,
        filename: _filenameOf(id),
      );
    } catch (error, stackTrace) {
      getLogger(
        'rich_text_image',
      ).warning('Failed to save an image of the document', error, stackTrace);
    }
  }

  bool _isSelected(Selection? selection) {
    if (selection == null) {
      return false;
    }

    final path = widget.node.path;
    final normalized = selection.normalized;

    return path >= normalized.start.path && path <= normalized.end.path;
  }

  /// The picture's shape, held for the length of a drag so the height follows
  /// the width instead of being worked out anew on every frame.
  double? _ratio;

  void _drag(double width, double? deltaX) {
    if (deltaX == null) {
      final settled = _dragging;
      final ratio = _ratio;

      setState(() {
        _dragging = null;
        _ratio = null;
      });

      if (settled != null) {
        // Both, so the block keeps its shape on the next build and after a
        // reload — a width alone would let the height be guessed again.
        unawaited(
          _resize(settled, height: ratio != null ? settled / ratio : null),
        );
      }

      return;
    }

    setState(() {
      _ratio ??= _measuredRatio();
      _dragging = max(_minWidth, (_dragging ?? width) + deltaX);
    });
  }

  void _select() {
    final editorState = context.read<EditorState>();

    editorState.selection = Selection.single(
      path: widget.node.path,
      startOffset: 0,
      endOffset: 1,
    );
  }

  double? _measuredRatio() {
    final box = _pictureKey.currentContext?.findRenderObject();

    if (box is! RenderBox || box.size.height <= 0) {
      return null;
    }

    return box.size.width / box.size.height;
  }

  Widget _image(double width) {
    final url = _url;
    final attachment = attachmentIdOf(url);

    if (attachment != null) {
      // Keyed by what it shows, not by where it sits: a document rebuilt from
      // the same text makes new nodes, and without this the picture would be a
      // new widget each time and download itself again.
      return _AttachmentImage(
        key: ValueKey('attachment:$attachment'),
        id: attachment,
        ratio: _ratio ?? _storedRatio,
        onError: _missing,
      );
    }

    final bytes = inlineImageBytes(url);

    // The width and nothing else, here as for an attachment: a picture given
    // only a width draws itself at that width and takes the height its own
    // shape asks for. Left to size itself it would come out at its pixel size,
    // which for a paste is whatever the screenshot happened to be.
    if (bytes != null) {
      // Straight from the paste that carried it, until a save stores it.
      return Image.memory(
        bytes,
        width: width,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _missing(),
      );
    }

    if (url == null || url.isEmpty) {
      return _missing();
    }

    return Image.network(
      url,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _missing(),
    );
  }

  // A picture holds no text, so it is selected whole: one offset before it and
  // one after, which is what the editor needs to draw over it and to delete it.

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _pictureKey.currentContext?.findRenderObject();

    return box is RenderBox ? Offset.zero & box.size : Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final size = _renderBox?.size;

    return size == null
        ? null
        : Rect.fromLTWH(-size.width / 2, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parent = context.findRenderObject();
    final picture = _pictureKey.currentContext?.findRenderObject();

    if (parent is RenderBox && picture is RenderBox) {
      return [
        picture.localToGlobal(Offset.zero, ancestor: parent) & picture.size,
      ];
    }

    final size = _renderBox?.size;

    return size == null ? [] : [Offset.zero & size];
  }

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox?.localToGlobal(offset) ?? offset;

  Widget _missing() {
    final theme = RichTextTheme.of(context);

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: theme.chipRadius,
        border: Border.all(color: theme.border),
      ),
      alignment: Alignment.center,
      child: Icon(
        FastEdgyIcons.of(context)[FastEdgyGlyph.imageMissing],
        size: 20,
        color: theme.mutedText,
      ),
    );
  }
}

/// An attached picture, asked for once at [imageDownloadWidth] and shown at
/// whatever width the block was given.
/// The two sizes are kept apart on purpose. [CachedApiImage] asks for the
/// variant matching the size it is laid out at, so a picture dragged narrower
/// would pull a smaller file down and come back blurred when widened again.
/// Giving it an explicit width pins what is requested, and the box around it
/// scales what is drawn.
class _AttachmentImage extends StatelessWidget {
  final int id;

  /// The shape the picture is known to have, when it has one: the placeholder
  /// takes it so the page does not move when the bytes land.
  final double? ratio;

  final Widget Function() onError;

  const _AttachmentImage({
    required this.id,
    required this.onError,
    this.ratio,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final width = imageDownloadWidth.toDouble();
    final height = ratio != null && ratio! > 0
        ? width / ratio!
        : _loadingHeight;

    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topLeft,
      // A width and nothing else: the height follows the picture's own shape,
      // and no resize mode is sent since there is no box to fit it into. Given
      // all the height it asks for, the box then takes that same shape.
      child: CachedApiImage(
        path: attachmentDownloadPath(id),
        width: width,
        // A shape rather than a spinner, and the application's own: a box that
        // settles into what its placeholder promised does not jump. Without a
        // size here the loading state asks for an unbounded height, which a
        // column cannot lay out.
        loadingBuilder: (context) => RichTextControls.of(context).placeholder(
          context,
          RichTextPlaceholderSpec(width: width, height: height),
        ),
        errorBuilder: (context, error, stackTrace) => onError(),
      ),
    );
  }
}

/// The bar held to resize the picture, on its trailing edge.
class _Handle extends StatefulWidget {
  final void Function(double? deltaX) onDrag;

  final VoidCallback onTap;

  const _Handle({required this.onDrag, required this.onTap});

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  bool _hovering = false;
  bool _holding = false;
  bool _dragged = false;
  double _travel = 0;

  double get _target => hasHoverPointer ? _handleWidth + 8 : 32;

  double get _slop => hasHoverPointer ? kPrecisePointerHitSlop : kTouchSlop;

  void _onDown(PointerDownEvent event) {
    _travel = 0;
    _dragged = false;
    setState(() => _holding = true);
  }

  void _onMove(PointerMoveEvent event) {
    if (!_dragged) {
      _travel += event.delta.distance;

      if (_travel < _slop) {
        return;
      }

      _dragged = true;
    }

    widget.onDrag(event.delta.dx);
  }

  void _onUp(PointerEvent event) {
    setState(() => _holding = false);
    widget.onDrag(null);

    if (!_dragged && event is PointerUpEvent) {
      widget.onTap();
    }

    _dragged = false;
    _travel = 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      // Same reason as the picture's own: absorbing the mouse here would read
      // as the pointer having left the picture, and the handle would take
      // itself away the moment it was aimed at.
      opaque: false,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SizedBox(
            width: _target,
            child: Center(
              child: Container(
                width: _handleWidth,
                height: 36,
                decoration: BoxDecoration(
                  color: _hovering || _holding
                      ? theme.ink
                      : theme.ink.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
