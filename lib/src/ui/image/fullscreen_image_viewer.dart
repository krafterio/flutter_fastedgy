/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

import '../icons.dart';
import '../theme/theme.dart';

/// One image the viewer shows: where to read it, and what to call it when saved.
class ViewerImage {
  final String path;
  final String filename;

  const ViewerImage({required this.path, required this.filename});
}

/// Full-screen image viewer: a page per image, zoom, arrows and Escape.
///
/// Knows nothing of what it shows: a storage path and a name per image, and
/// what to do when one is saved or deleted. Saving goes through [onSave] rather
/// than a platform gallery — macOS has no camera roll.
class FullScreenImageViewer extends StatefulWidget {
  final List<ViewerImage> images;
  final int initialIndex;

  /// Saves the image at that index; null hides the button.
  final Future<void> Function(int index)? onSave;

  /// Deletes the image at that index; answers whether it is gone.
  final Future<bool> Function(int index)? onDelete;

  const FullScreenImageViewer({
    required this.images,
    super.key,
    this.initialIndex = 0,
    this.onSave,
    this.onDelete,
  });

  static void show(
    BuildContext context, {
    required List<ViewerImage> images,
    int initialIndex = 0,
    Future<void> Function(int index)? onSave,
    Future<bool> Function(int index)? onDelete,
  }) {
    if (images.isEmpty) {
      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenImageViewer(
              images: images,
              initialIndex: initialIndex.clamp(0, images.length - 1),
              onSave: onSave,
              onDelete: onDelete,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _index;
  late List<ViewerImage> _images;

  final Map<int, TransformationController> _transforms = {};

  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _images = [...widget.images];
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();

    for (final controller in _transforms.values) {
      controller.dispose();
    }

    super.dispose();
  }

  TransformationController _transformOf(int index) =>
      _transforms.putIfAbsent(index, TransformationController.new);

  void _resetZoom() => _transformOf(_index).value = Matrix4.identity();

  bool get _hasMultiple => _images.length > 1;

  /// The index in the caller's list, which never shrinks as pages are removed.
  int _sourceIndexOf(ViewerImage image) => widget.images.indexOf(image);

  Future<void> _save() async {
    final onSave = widget.onSave;

    if (_saving || onSave == null) {
      return;
    }

    setState(() => _saving = true);

    try {
      await onSave(_sourceIndexOf(_images[_index]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;

    if (_deleting || onDelete == null) {
      return;
    }

    setState(() => _deleting = true);

    try {
      final deleted = await onDelete(_sourceIndexOf(_images[_index]));

      if (!deleted || !mounted) {
        return;
      }

      _images.removeAt(_index);

      if (_images.isEmpty) {
        Navigator.of(context).pop();

        return;
      }

      final next = _index >= _images.length ? _images.length - 1 : _index;

      setState(() {
        _index = next;
        _pageController = PageController(initialPage: next);
      });
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _go(int delta) {
    final next = _index + delta;

    if (next < 0 || next >= _images.length) {
      return;
    }

    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// A desktop viewer is driven from the keyboard as much as from the mouse.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      case LogicalKeyboardKey.arrowRight:
        _go(1);
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
      default:
        return KeyEventResult.ignored;
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final icons = FastEdgyIcons.of(context);
    final typography = FastEdgyTheme.of(context).typography;
    final safePadding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _images.length,
              onPageChanged: (index) => setState(() => _index = index),
              physics: _hasMultiple
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) => InteractiveViewer(
                transformationController: _transformOf(index),
                maxScale: 5,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: CachedApiImage(
                    path: _images[index].path,
                    mode: ImageMode.contain,
                    format: 'webp',
                    // device pixel ratio asks the server for a needless giant.
                    autoCalculatePhysicalDimensions: false,
                    // A full-size picture is a real download, and the viewer
                    // opens on black: without this it reads as an image that
                    // failed rather than one on its way.
                    loadingBuilder: (context) => Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    errorBuilder: (context, error, stackTrace) => Icon(
                      icons[FastEdgyGlyph.imageMissing],
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: safePadding.top + 12,
              right: 16,
              child: _ViewerButton(
                icon: icons[FastEdgyGlyph.close],
                label: t('Close'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: safePadding.top + 12,
              left: 16,
              child: Row(
                children: [
                  _ViewerButton(
                    icon: icons[FastEdgyGlyph.resetZoom],
                    label: t('Reset zoom'),
                    onTap: _resetZoom,
                  ),
                  if (widget.onSave != null) ...[
                    const SizedBox(width: 12),
                    _ViewerButton(
                      icon: icons[FastEdgyGlyph.download],
                      label: t('Download'),
                      busy: _saving,
                      onTap: _save,
                    ),
                  ],
                  if (widget.onDelete != null) ...[
                    const SizedBox(width: 12),
                    _ViewerButton(
                      icon: icons[FastEdgyGlyph.delete],
                      label: t('Remove'),
                      busy: _deleting,
                      onTap: _delete,
                    ),
                  ],
                ],
              ),
            ),
            if (_hasMultiple) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ViewerButton(
                    icon: icons[FastEdgyGlyph.previous],
                    label: t('Previous'),
                    onTap: _index > 0 ? () => _go(-1) : null,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ViewerButton(
                    icon: icons[FastEdgyGlyph.next],
                    label: t('Next'),
                    onTap: _index < _images.length - 1 ? () => _go(1) : null,
                  ),
                ),
              ),
              Positioned(
                bottom: safePadding.bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_index + 1} / ${_images.length}',
                      style: typography.mono.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;

  /// Null reads as unavailable.
  final VoidCallback? onTap;

  const _ViewerButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;

    return Tooltip(
      message: label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: enabled ? 0.5 : 0.25),
              shape: BoxShape.circle,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    icon,
                    size: 18,
                    color: Colors.white.withValues(alpha: enabled ? 1 : 0.4),
                  ),
          ),
        ),
      ),
    );
  }
}
